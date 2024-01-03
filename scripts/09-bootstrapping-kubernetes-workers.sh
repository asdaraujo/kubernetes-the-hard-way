#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## Bootstrapping the Kubernetes Worker Nodes

K8S_VERSION=1.26.12
CRI_VERSION=1.29.0
RUNC_VERSION=1.1.11
CNI_VERSION=1.4.0
CONTAINERD_VERSION=1.7.11
GOOGLE_URL=https://storage.googleapis.com/kubernetes-release

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region $REGION \
  --format 'value(address)')

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Install the OS dependencies: \$(hostname -s)"

if [[ ! -f /usr/bin/socat || ! -f /usr/sbin/conntrack || ! -f /usr/sbin/ipset ]]; then
  sudo apt-get update
  sudo apt-get -y install socat conntrack ipset
fi

logmsg "Disable Swap: \$(hostname -s)"

sudo swapoff -a

logmsg "Create the installation directories: \$(hostname -s)"

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

logmsg "Download and Install Worker Binaries: \$(hostname -s)"

BINARIES=(
    /usr/local/bin/crictl     https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRI_VERSION}/crictl-v${CRI_VERSION}-linux-amd64.tar.gz               "tar -xvf crictl-v${CRI_VERSION}-linux-amd64.tar.gz; chmod +x crictl; sudo mv crictl /usr/local/bin/"
    /usr/local/bin/runc       https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.amd64                                                   "sudo mv runc.amd64 runc; chmod +x runc; sudo mv runc /usr/local/bin/"
    /opt/cni/bin/loopback     https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-amd64-v${CNI_VERSION}.tgz           "sudo tar -xvf cni-plugins-linux-amd64-v${CNI_VERSION}.tgz -C /opt/cni/bin/"
    /bin/containerd           https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz  "mkdir containerd; tar -xvf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C containerd; sudo mv containerd/bin/* /bin/"
    /usr/local/bin/kubectl    ${GOOGLE_URL}/release/v${K8S_VERSION}/bin/linux/amd64/kubectl                                                                          "chmod +x kubectl; sudo mv kubectl  /usr/local/bin/"
    /usr/local/bin/kube-proxy ${GOOGLE_URL}/release/v${K8S_VERSION}/bin/linux/amd64/kube-proxy                                                                       "chmod +x kube-proxy; sudo mv kube-proxy /usr/local/bin/"
    /usr/local/bin/kubelet    ${GOOGLE_URL}/release/v${K8S_VERSION}/bin/linux/amd64/kubelet                                                                          "chmod +x kubelet; sudo mv kubelet /usr/local/bin/"
)

set -- "\${BINARIES[@]}"
while [[ \$# -gt 0 ]]; do
    TARGET=\$1; shift
    URL=\$1; shift
    INSTALL_CMDS=\$1; shift
  if [[ ! -f \$TARGET ]]; then
    echo "Downloading \$URL"
    wget --show-progress --https-only --timestamping \$URL
    echo "Installing: \$INSTALL_CMDS"
    eval "\$INSTALL_CMDS"
  fi
done

### Configure CNI Networking

logmsg "Retrieve the Pod CIDR range for the current compute instance: \$(hostname -s)"

POD_CIDR=\$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod-cidr)

logmsg "Create the bridge network configuration file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "0.4.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "\${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

# Create the loopback network configuration file:

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "0.4.0",
    "name": "lo",
    "type": "loopback"
}
EOF

# Configure containerd

# Create the containerd configuration file:

sudo mkdir -p /etc/containerd/

cat << EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
EOF

logmsg "Create the containerd.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

logmsg "Configure the Kubelet: \$(hostname -s)"

sudo cp -f ~/certs/{\${HOSTNAME}-key.pem,\${HOSTNAME}.pem} /var/lib/kubelet/
sudo cp -f ~/kubeconfig/\${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp -f ~/certs/ca.pem /var/lib/kubernetes/

logmsg "Create the kubelet-config.yaml configuration file: \$(hostname -s)"

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "\${POD_CIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/\${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/\${HOSTNAME}-key.pem"
EOF

logmsg "Create the kubelet.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Configure the Kubernetes Proxy: \$(hostname -s)"

sudo cp -f ~/kubeconfig/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

logmsg "Create the kube-proxy-config.yaml configuration file: \$(hostname -s)"

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF

logmsg "Create the kube-proxy.service systemd unit file: \$(hostname -s)"

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Start the Worker Services: \$(hostname -s)"

sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl restart containerd kubelet kube-proxy

CMDEOF
)

for instance in "${ALL_WORKERS[@]}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

logmsg "Verification: List the registered Kubernetes nodes"

gcloud compute ssh --ssh-key-file=~/.ssh/id_rsa ${ALL_CONTROLLERS[@]:0:1} \
  --command "kubectl get nodes --kubeconfig ~/kubeconfig/admin.kubeconfig"
