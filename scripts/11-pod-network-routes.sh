#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

### Provisioning Pod Network Routes

## The Routing Table

logmsg "Print the internal IP address and Pod CIDR range for each worker instance:"

for instance in "${ALL_WORKERS[@]}"; do
  gcloud compute instances describe ${instance} \
    --format 'value[separator=" "](networkInterfaces[0].networkIP,metadata.items[0].value)'
done

## Routes

logmsg "Create network routes for each worker instance:"

for instance in "${ALL_WORKERS[@]}"; do
  gcloud compute routes create ${NAMESPACE}-route-$(echo $(pod_cidr $instance) | sed 's/[^0-9]/-/g') \
    --network ${NETWORK} \
    --next-hop-address $(private_ip $instance) \
    --destination-range $(pod_cidr $instance)
done

logmsg "List the routes in the  VPC network:"

gcloud compute routes list --filter=network:${NETWORK}
