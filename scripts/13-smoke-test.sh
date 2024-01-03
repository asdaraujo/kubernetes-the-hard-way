#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

logmsg "Smoke Test"

## Data Encryption

logmsg "Delete generic secret, if it already exists:"

kubectl delete secret ${NAMESPACE} || true

logmsg "Create a generic secret:"

kubectl create secret generic ${NAMESPACE} \
  --from-literal="mykey=mydata"

logmsg "Print a hexdump of the secret stored in etcd:"

gcloud compute ssh --ssh-key-file=${SSH_KEY_FILE} ${CONTROLLER_PREFIX}-0 \
  --command "sudo ETCDCTL_API=3 etcdctl get \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem\
  /registry/secrets/default/${NAMESPACE} | hexdump -C"

## Deployments

logmsg "Create a deployment for the [nginx](https://nginx.org/en/) web server:"

kubectl create deployment nginx --image=nginx || true

logmsg "Wait for the nginx pod to be running"

kubectl wait pod -l app=nginx --for=jsonpath='{.status.phase}'=Running

logmsg "List the pod created by the nginx deployment:"

kubectl get pods -l app=nginx

### Port Forwarding

logmsg "Retrieve the full name of the nginx pod:"

POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")

logmsg "Forward port 8080 on your local machine to port 80 of the nginx pod:"

kubectl port-forward $POD_NAME 8080:80 &
PORT_FWD_PID=$!
sleep 3
echo "Running on background with PID $PORT_FWD_PID"

logmsg "Make an HTTP request using the forwarding address:"

echo "curl --head http://127.0.0.1:8080"
curl --head http://127.0.0.1:8080

logmsg "Stop the port forwarding to the nginx pod:"

echo "kill $PORT_FWD_PID"
kill $PORT_FWD_PID

### Logs

logmsg "Print the nginx pod logs:"

kubectl logs $POD_NAME

### Exec

logmsg "Print the nginx version by executing the nginx -v command in the nginx container:"

kubectl exec -ti $POD_NAME -- nginx -v

## Services

logmsg "Expose the nginx deployment using a [NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) service:"

kubectl expose deployment nginx --port 80 --type NodePort || true

logmsg "Retrieve the node port assigned to the nginx service:"

NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')
echo "NODE_PORT=$NODE_PORT"

logmsg "Delete the firewall rule, if it was created previously:"

gcloud -q compute firewall-rules delete ${FW_NGINX} || true

logmsg "Create a firewall rule that allows remote access to the nginx node port:"

gcloud compute firewall-rules create ${FW_NGINX} \
  --allow=tcp:${NODE_PORT} \
  --network=${NETWORK} || true

logmsg "Retrieve the external IP address of a worker instance:"

EXTERNAL_IP=$(gcloud compute instances describe ${WORKER_PREFIX}-0 \
  --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
echo "EXTERNAL_IP=$EXTERNAL_IP"

logmsg "Make an HTTP request using the external IP address and the nginx node port:"

curl -I http://${EXTERNAL_IP}:${NODE_PORT}

logmsg "Delete generic secret, if it already exists:"

kubectl delete secret ${NAMESPACE} || true

logmsg "Delete nginx deployment:"

kubectl delete deployment nginx || true

logmsg "Delete nginx NodePort service:"

kubectl get service -l app=nginx

logmsg "Delete the firewall rule:"

gcloud -q compute firewall-rules delete ${FW_NGINX} || true
