#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## Bootstrapping an etcd Cluster Member

ETCD_VER=v3.5.11
GOOGLE_URL=https://storage.googleapis.com/etcd

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current compute instance:"

ETCD_NAME=\$(hostname -s)

logmsg "Download the official etcd release binaries: \${ETCD_NAME}"

curl -s -L ${GOOGLE_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

logmsg "Extract and install the etcd server and the etcdctl command line utility: \${ETCD_NAME}"

rm -rf /tmp/etcd-download
mkdir /tmp/etcd-download
tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download --strip-components=1
sudo mv /tmp/etcd-download/etcd* /usr/local/bin/
rm -rf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz /tmp/etcd-download

logmsg "Configure the etcd Server: \${ETCD_NAME}"

sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo cp -f ~/certs/ca.pem ~/certs/kubernetes-key.pem ~/certs/kubernetes.pem /etc/etcd/

logmsg "The instance internal IP address will be used to serve client requests and communicate with etcd cluster peers. Retrieve the internal IP address for the current compute instance: \${ETCD_NAME}"

INTERNAL_IP=\$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

logmsg "Create the etcd.service systemd unit file: \${ETCD_NAME}"

cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name \${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://\${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://\${INTERNAL_IP}:2380 \\
  --listen-client-urls https://\${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://\${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${CONTROLLER_PREFIX}-0=https://10.240.0.10:2380,${CONTROLLER_PREFIX}-1=https://10.240.0.11:2380,${CONTROLLER_PREFIX}-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

logmsg "Start the etcd Server: \${ETCD_NAME}"

sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl restart etcd
CMDEOF
)

for instance in ${CONTROLLER_PREFIX}-{0..2}; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

logmsg "Verification: List the etcd cluster members:"

gcloud compute ssh ${CONTROLLER_PREFIX}-0 --ssh-key-file=${SSH_KEY_FILE} --command="
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/ca.pem \
    --cert=/etc/etcd/kubernetes.pem \
    --key=/etc/etcd/kubernetes-key.pem"
