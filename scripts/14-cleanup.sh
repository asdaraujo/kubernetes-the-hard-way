#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## Networking

#logmsg "Delete the external load balancer network resources:"
#
#gcloud -q compute forwarding-rules delete kubernetes-forwarding-rule \
#  --region $(gcloud config get-value compute/region)

#gcloud -q compute target-pools delete kubernetes-target-pool

#gcloud -q compute http-health-checks delete kubernetes

logmsg "Delete the network routes:"

INSTANCES=$(gcloud -q compute routes list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute routes delete \
    ${INSTANCES} || true
fi

logmsg "Delete the controller and worker compute instances:"

INSTANCES=$(gcloud -q compute instances list --filter=tags:${NAMESPACE} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute instances delete \
    ${INSTANCES} \
    --zone ${ZONE} \
    --delete-disks=all || true
fi

logmsg "Delete the static ip address:"

INSTANCES=$(gcloud -q compute addresses list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute addresses delete ${INSTANCES} || true
fi

logmsg "Delete the firewall rules:"

INSTANCES=$(gcloud -q compute firewall-rules list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute firewall-rules delete \
    ${INSTANCES} || true
fi

logmsg "Delete the subnet:"

INSTANCES=$(gcloud -q compute networks subnets list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute networks subnets delete ${INSTANCES} || true
fi

logmsg "Delete the network VPC:"

INSTANCES=$(gcloud -q compute networks list --filter=name:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute networks delete ${INSTANCES} || true
fi
