#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## Client Authentication Configs

### Kubernetes Public IP Address

logmsg "Retrieve the static IP address:"

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region ${REGION} \
  --format 'value(address)')

### The kubelet Kubernetes Configuration File

logmsg "Generate a kubeconfig file for each worker node:"

for instance in "${ALL_WORKERS[@]}"; do
  kubectl config set-cluster ${NAMESPACE} \
    --certificate-authority=${CERTS_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${KUBECONFIG_DIR}/${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=${CERTS_DIR}/${instance}.pem \
    --client-key=${CERTS_DIR}/${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${KUBECONFIG_DIR}/${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=${NAMESPACE} \
    --user=system:node:${instance} \
    --kubeconfig=${KUBECONFIG_DIR}/${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${KUBECONFIG_DIR}/${instance}.kubeconfig
done

### The kube-proxy Kubernetes Configuration File

logmsg "Generate a kubeconfig file for the kube-proxy service:"

kubectl config set-cluster ${NAMESPACE} \
  --certificate-authority=${CERTS_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=${KUBECONFIG_DIR}/kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=${CERTS_DIR}/kube-proxy.pem \
  --client-key=${CERTS_DIR}/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_DIR}/kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=${NAMESPACE} \
  --user=system:kube-proxy \
  --kubeconfig=${KUBECONFIG_DIR}/kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=${KUBECONFIG_DIR}/kube-proxy.kubeconfig

### The kube-controller-manager Kubernetes Configuration File

logmsg "Generate a kubeconfig file for the kube-controller-manager service:"

kubectl config set-cluster ${NAMESPACE} \
  --certificate-authority=${CERTS_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${KUBECONFIG_DIR}/kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=${CERTS_DIR}/kube-controller-manager.pem \
  --client-key=${CERTS_DIR}/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_DIR}/kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=${NAMESPACE} \
  --user=system:kube-controller-manager \
  --kubeconfig=${KUBECONFIG_DIR}/kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=${KUBECONFIG_DIR}/kube-controller-manager.kubeconfig

### The kube-scheduler Kubernetes Configuration File

logmsg "Generate a kubeconfig file for the kube-scheduler service:"

kubectl config set-cluster ${NAMESPACE} \
  --certificate-authority=${CERTS_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${KUBECONFIG_DIR}/kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=${CERTS_DIR}/kube-scheduler.pem \
  --client-key=${CERTS_DIR}/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_DIR}/kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=${NAMESPACE} \
  --user=system:kube-scheduler \
  --kubeconfig=${KUBECONFIG_DIR}/kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=${KUBECONFIG_DIR}/kube-scheduler.kubeconfig

### The admin Kubernetes Configuration File

logmsg "Generate a kubeconfig file for the admin user:"

kubectl config set-cluster ${NAMESPACE} \
  --certificate-authority=${CERTS_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${KUBECONFIG_DIR}/admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=${CERTS_DIR}/admin.pem \
  --client-key=${CERTS_DIR}/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_DIR}/admin.kubeconfig

kubectl config set-context default \
  --cluster=${NAMESPACE} \
  --user=admin \
  --kubeconfig=${KUBECONFIG_DIR}/admin.kubeconfig

kubectl config use-context default --kubeconfig=${KUBECONFIG_DIR}/admin.kubeconfig

## Distribute the Kubernetes Configuration Files

for instance in "${ALL_WORKERS[@]}"; do
  logmsg "Copy the appropriate kubelet and kube-proxy kubeconfig files to worker instance: $instance"
  gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${KUBECONFIG_DIR}/{${instance}.kubeconfig,kube-proxy.kubeconfig} ${instance}:~/kubeconfig/
done

for instance in "${ALL_CONTROLLERS[@]}"; do
  logmsg "Copy the appropriate kube-controller-manager and kube-scheduler kubeconfig files to controller instance: $instance"
  gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${KUBECONFIG_DIR}/{admin.kubeconfig,kube-controller-manager.kubeconfig,kube-scheduler.kubeconfig} ${instance}:~/kubeconfig/
done
