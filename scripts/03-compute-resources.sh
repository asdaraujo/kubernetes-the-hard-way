#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

### VPC Networking

logmsg "Create the custom VPC network:"

gcloud compute networks create ${NETWORK} --subnet-mode custom

logmsg "Create the subnet in the VPC network:"

gcloud compute networks subnets create ${SUBNET} \
  --network ${NETWORK} \
  --range 10.240.0.0/24

### Firewall Rules

logmsg "Create a firewall rule that allows internal communication across all protocols:"

gcloud compute firewall-rules create ${FW_INTERNAL} \
  --allow tcp,udp,icmp \
  --network ${NETWORK} \
  --source-ranges 10.240.0.0/24,10.200.0.0/16

logmsg "Create a firewall rule that allows external SSH, ICMP, and HTTPS:"

gcloud compute firewall-rules create ${FW_EXTERNAL} \
  --allow tcp:22,tcp:6443,icmp \
  --network ${NETWORK} \
  --source-ranges 0.0.0.0/0

logmsg "List the firewall rules in the VPC network:"

gcloud compute firewall-rules list --filter="network:${NETWORK}"

### Kubernetes Public IP Address

logmsg "Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:"

gcloud compute addresses create ${IP_ADDRESS} \
  --region ${REGION}

logmsg "Verify the static IP address was created in your default compute region:"

gcloud compute addresses list --filter="name=('${IP_ADDRESS}')"

### Kubernetes Controllers

logmsg "Create three compute instances which will host the Kubernetes control plane:"

for i in ${CONTROLLER_PREFIX}-{0..2}; do
  gcloud compute instances create ${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-2004-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip 10.240.0.1${i##*-} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet ${SUBNET} \
    --tags ${NAMESPACE},controller
done

### Kubernetes Workers

logmsg "Create three compute instances which will host the Kubernetes worker nodes:"

for i in ${WORKER_PREFIX}-{0..2}; do
  gcloud compute instances create ${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-2004-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --metadata pod-cidr=10.200.${i##*-}.0/24 \
    --private-network-ip 10.240.0.2${i##*-} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet ${SUBNET} \
    --tags ${NAMESPACE},worker
done

### Verification

logmsg "List the compute instances in your default compute zone:"

gcloud compute instances list --filter="tags.items=${NAMESPACE}"

## Configuring SSH Access

logmsg "Test SSH access to the compute instances:"

for i in ${CONTROLLER_PREFIX}-{0..2} ${WORKER_PREFIX}-{0..2}; do
  gcloud compute ssh ${i} --ssh-key-file=${SSH_KEY_FILE} --command="mkdir -p certs config kubeconfig; hostname"
done
