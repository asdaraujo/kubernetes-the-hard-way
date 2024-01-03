#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## The Admin Kubernetes Configuration File

logmsg "Generate a kubeconfig file suitable for authenticating as the `admin` user:"

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region ${REGION} \
  --format 'value(address)')

kubectl config set-cluster ${NAMESPACE} \
  --certificate-authority=${CERTS_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

kubectl config set-credentials admin \
  --client-certificate=${CERTS_DIR}/admin.pem \
  --client-key=${CERTS_DIR}/admin-key.pem

kubectl config set-context ${NAMESPACE} \
  --cluster=${NAMESPACE} \
  --user=admin

logmsg "Set default context in a local .kubeconfig"

cat > ${BASE_DIR}/.kubeconfig <<EOF
apiVersion: v1
kind: Config
current-context: ${NAMESPACE}
EOF

## Verification

logmsg "Check the version of the remote Kubernetes cluster:"

kubectl version

logmsg "List the nodes in the remote Kubernetes cluster:"

kubectl get nodes
