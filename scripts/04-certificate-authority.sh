#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

function filter_stderr() {
  egrep -v "INFO|This certificate lacks|Issuance and Management|Publicly-Trusted Certificates|Information Requirements"
}

## Certificate Authority

logmsg "Generate the CA configuration file, certificate, and private key:"

cat > ${CONFIG_DIR}/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ${CONFIG_DIR}/ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "CA",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert -initca ${CONFIG_DIR}/ca-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/ca

## Client and Server Certificates

### The Admin Client Certificate

logmsg "Generate the admin client certificate and private key:"

cat > ${CONFIG_DIR}/admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -profile=kubernetes \
  ${CONFIG_DIR}/admin-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/admin

### The Kubelet Client Certificates

for instance in "${ALL_WORKERS[@]}"; do
  logmsg "Generate a certificate and private key for Kubernetes worker node: $instance"
  cat > ${CONFIG_DIR}/${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

  EXTERNAL_IP=$(gcloud compute instances describe ${instance} \
    --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')

  INTERNAL_IP=$(gcloud compute instances describe ${instance} \
    --format 'value(networkInterfaces[0].networkIP)')

  cfssl gencert \
    -ca=${CERTS_DIR}/ca.pem \
    -ca-key=${CERTS_DIR}/ca-key.pem \
    -config=${CONFIG_DIR}/ca-config.json \
    -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
    -profile=kubernetes \
    ${CONFIG_DIR}/${instance}-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/${instance}
done

### The Controller Manager Client Certificate

logmsg "Generate the kube-controller-manager client certificate and private key:"

cat > ${CONFIG_DIR}/kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -profile=kubernetes \
  ${CONFIG_DIR}/kube-controller-manager-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/kube-controller-manager

### The Kube Proxy Client Certificate

logmsg "Generate the kube-proxy client certificate and private key:"

cat > ${CONFIG_DIR}/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -profile=kubernetes \
  ${CONFIG_DIR}/kube-proxy-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/kube-proxy

### The Scheduler Client Certificate

logmsg "Generate the kube-scheduler client certificate and private key:"

cat > ${CONFIG_DIR}/kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -profile=kubernetes \
  ${CONFIG_DIR}/kube-scheduler-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/kube-scheduler

### The Kubernetes API Server Certificate

logmsg "Generate the Kubernetes API Server certificate and private key:"

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region ${REGION} \
  --format 'value(address)')

KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local

cat > ${CONFIG_DIR}/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

LIST_OF_CONTROLLER_IPS=""
for h in "${ALL_CONTROLLERS[@]}"; do
  if [[ ! -z $LIST_OF_CONTROLLER_IPS ]]; then
    LIST_OF_CONTROLLER_IPS="${LIST_OF_CONTROLLER_IPS},"
  fi
  LIST_OF_CONTROLLER_IPS="${LIST_OF_CONTROLLER_IPS}$(private_ip $h)"
done

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -hostname=10.32.0.1,${LIST_OF_CONTROLLER_IPS},${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,${KUBERNETES_HOSTNAMES} \
  -profile=kubernetes \
  ${CONFIG_DIR}/kubernetes-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/kubernetes

## The Service Account Key Pair

logmsg "Generate the service-account certificate and private key:"

cat > ${CONFIG_DIR}/service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "C": "AU",
      "ST": "Victoria",
      "L": "Melbourne"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CERTS_DIR}/ca.pem \
  -ca-key=${CERTS_DIR}/ca-key.pem \
  -config=${CONFIG_DIR}/ca-config.json \
  -profile=kubernetes \
  ${CONFIG_DIR}/service-account-csr.json 2> >(filter_stderr >&2) | cfssljson -bare ${CERTS_DIR}/service-account

## Distribute the Client and Server Certificates

for instance in "${ALL_WORKERS[@]}"; do
  logmsg "Copy the appropriate certificates and private keys to worker instance: $instance"
  gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${CERTS_DIR}/{ca.pem,${instance}-key.pem,${instance}.pem} ${instance}:~/certs/
done

for instance in "${ALL_CONTROLLERS[@]}"; do
  logmsg "Copy the appropriate certificates and private keys to controller instance: $instance"
  gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${CERTS_DIR}/{ca.pem,ca-key.pem,kubernetes-key.pem,kubernetes.pem,service-account-key.pem,service-account.pem} ${instance}:~/certs/
done
