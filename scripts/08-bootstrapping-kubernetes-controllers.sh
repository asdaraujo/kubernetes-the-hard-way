#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## Bootstrapping the Kubernetes Control Plane

K8S_VERSION=v1.26.12
GOOGLE_URL=https://storage.googleapis.com/kubernetes-release

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region $REGION \
  --format 'value(address)')

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Create the Kubernetes configuration directory: \$(hostname -s)"

sudo mkdir -p /etc/kubernetes/config

logmsg "Download the official Kubernetes release binaries and install them: \$(hostname -s)"

for binary in kube-apiserver kube-controller-manager kube-scheduler kubectl; do
  if [[ ! -f /usr/local/bin/\${binary} ]]; then
    wget -q --show-progress --https-only --timestamping \
      "${GOOGLE_URL}/release/${K8S_VERSION}/bin/linux/amd64/\${binary}"
    chmod +x \${binary}
    sudo mv \${binary} /usr/local/bin/
  fi
done

logmsg "Configure the Kubernetes API Server: \$(hostname -s)"

sudo mkdir -p /var/lib/kubernetes/

sudo cp -f ~/certs/{ca.pem,ca-key.pem,kubernetes-key.pem,kubernetes.pem,service-account-key.pem,service-account.pem} \
  ~/config/encryption-config.yaml \
  /var/lib/kubernetes/

logmsg "The instance internal IP address will be used to advertise the API Server to members of the cluster. Retrieve the internal IP address for the current compute instance: \$(hostname -s)"

INTERNAL_IP=\$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

logmsg "Create the kube-apiserver.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=\${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Configure the Kubernetes Controller Manager: \$(hostname -s)"

logmsg "Move the kube-controller-manager kubeconfig into place: \$(hostname -s)"

sudo cp -f ~/kubeconfig/kube-controller-manager.kubeconfig /var/lib/kubernetes/

logmsg "Create the kube-controller-manager.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Configure the Kubernetes Scheduler: \$(hostname -s)"

logmsg "Move the kube-scheduler kubeconfig into place: \$(hostname -s)"

sudo cp -f ~/kubeconfig/kube-scheduler.kubeconfig /var/lib/kubernetes/

logmsg "Create the kube-scheduler.yaml configuration file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

logmsg "Create the kube-scheduler.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Start the Controller Services: \$(hostname -s)"

sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl restart kube-apiserver kube-controller-manager kube-scheduler

logmsg "Allow up to 10 seconds for the Kubernetes API Server to fully initialize: \$(hostname -s)"
sleep 10

logmsg "Enable HTTP Health Checks: \$(hostname -s)"

logmsg "Install a basic web server to handle HTTP health checks: \$(hostname -s)"

if [[ ! -f /usr/sbin/nginx ]]; then
  sudo apt-get update
  sudo apt-get install -y nginx
fi

cat > ~/config/kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF

sudo cp -f ~/config/kubernetes.default.svc.cluster.local \
  /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

sudo rm -f /etc/nginx/sites-enabled/kubernetes.default.svc.cluster.local
sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/kubernetes.default.svc.cluster.local

sudo systemctl enable nginx
sudo systemctl restart nginx

logmsg "Verification: \$(hostname -s)"

kubectl cluster-info --kubeconfig ~/kubeconfig/admin.kubeconfig

logmsg "Test the nginx HTTP health check proxy: \$(hostname -s)"

curl -s -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz; echo
[[ \$(curl -s -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz | grep -i ok | wc -l) -eq 2 ]]

CMDEOF
)

for instance in ${CONTROLLER_PREFIX}-{0..2}; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD"
done

## RBAC for Kubelet Authorization

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Create the system:kube-apiserver-to-kubelet [ClusterRole](https://kubernetes.io/docs/admin/authorization/rbac/#role-and-clusterrole) with permissions to access the Kubelet API and perform most common tasks associated with managing pods:"

cat <<EOF | kubectl apply --kubeconfig ~/kubeconfig/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

logmsg "The Kubernetes API Server authenticates to the Kubelet as the kubernetes user using the client certificate as defined by the --kubelet-client-certificate flag."

logmsg "Bind the system:kube-apiserver-to-kubelet ClusterRole to the kubernetes user:"

cat <<EOF | kubectl apply --kubeconfig ~/kubeconfig/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

## The Kubernetes Frontend Load Balancer

logmsg "Create the external load balancer network resources:"

logmsg "Create the health check for the external load balancer:"

gcloud compute http-health-checks create ${HEALTH_CHECK} \
  --description "Kubernetes Health Check" \
  --host "kubernetes.default.svc.cluster.local" \
  --request-path "/healthz"

logmsg "Create firewall rule for the external load balancer:"

gcloud compute firewall-rules create ${FW_HEALTHCHECK} \
  --network ${NETWORK} \
  --source-ranges 209.85.152.0/22,209.85.204.0/22,35.191.0.0/16 \
  --allow tcp

logmsg "Create target pool for the external load balancer:"

gcloud compute target-pools create ${TARGET_POOL} \
  --http-health-check ${HEALTH_CHECK} \
  --region ${REGION}

logmsg "Add backend instances to the target pool:"

gcloud compute target-pools add-instances ${TARGET_POOL} \
 --instances ${CONTROLLER_PREFIX}-0,${CONTROLLER_PREFIX}-1,${CONTROLLER_PREFIX}-2 \
 --instances-zone ${ZONE}

logmsg "Create forwarding rules:"

gcloud compute forwarding-rules create ${FWD_RULE} \
  --address ${KUBERNETES_PUBLIC_ADDRESS} \
  --ports 6443 \
  --region ${REGION} \
  --target-pool ${TARGET_POOL}

logmsg "Verification:"

logmsg "Make a HTTP request for the Kubernetes version info:"

curl -i -s --cacert ~/certs/ca.pem https://${KUBERNETES_PUBLIC_ADDRESS}:6443/version

CMDEOF
)

gcloud compute ssh ${CONTROLLER_PREFIX}-0 --ssh-key-file=${SSH_KEY_FILE} --command="$CMD"
