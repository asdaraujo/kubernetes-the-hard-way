#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

### Provisioning Pod Network Routes

## The Routing Table

logmsg "Print the internal IP address and Pod CIDR range for each worker instance:"

for instance in ${WORKER_PREFIX}-{0..2}; do
  gcloud compute instances describe ${instance} \
    --format 'value[separator=" "](networkInterfaces[0].networkIP,metadata.items[0].value)'
done

## Routes

logmsg "Create network routes for each worker instance:"

for i in 0 1 2; do
  gcloud compute routes create ${NAMESPACE}-route-10-200-${i}-0-24 \
    --network ${NETWORK} \
    --next-hop-address 10.240.0.2${i} \
    --destination-range 10.200.${i}.0/24
done

logmsg "List the routes in the  VPC network:"

gcloud compute routes list --filter=network:${NETWORK}
