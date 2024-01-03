if [[ ${0:-defaults.sh} != "defaults.sh" ]]; then
  set -o errexit
  set -o nounset
  set -o pipefail
fi

function logmsg() {
  local msg=$1
  echo "${C_YELLOW}${msg}${C_NORMAL}"
}

C_NORMAL="$(echo -e "\033[0m")"
C_BOLD="$(echo -e "\033[1m")"
C_DIM="$(echo -e "\033[2m")"
C_BLACK="$(echo -e "\033[30m")"
C_RED="$(echo -e "\033[31m")"
C_GREEN="$(echo -e "\033[32m")"
C_YELLOW="$(echo -e "\033[33m")"
C_BLUE="$(echo -e "\033[34m")"
C_WHITE="$(echo -e "\033[97m")"
C_BG_GREEN="$(echo -e "\033[42m")"
C_BG_RED="$(echo -e "\033[101m")"
C_BG_MAGENTA="$(echo -e "\033[105m")"

NAMESPACE=araujo-kthw
NETWORK=${NAMESPACE}-vpc
SUBNET=${NAMESPACE}-subnet
FW_INTERNAL=${NAMESPACE}-allow-internal
FW_EXTERNAL=${NAMESPACE}-allow-external
FW_HEALTHCHECK=${NAMESPACE}-allow-health-check
FW_NGINX=${NAMESPACE}-allow-nginx-service
IP_ADDRESS=${NAMESPACE}-ip-address
CONTROLLER_PREFIX=${NAMESPACE}-controller
WORKER_PREFIX=${NAMESPACE}-worker
HEALTH_CHECK=${NAMESPACE}-k8s-health-check
TARGET_POOL=${NAMESPACE}-target-pool
FWD_RULE=${NAMESPACE}-forwarding-rule

SSH_KEY_FILE=~/.ssh/id_rsa

if [[ ! -z ${BASE_DIR:-} ]]; then
  CONFIG_DIR=${BASE_DIR}/config
  CERTS_DIR=${BASE_DIR}/certs
  KUBECONFIG_DIR=${BASE_DIR}/kubeconfig
  mkdir -p ${CONFIG_DIR} ${CERTS_DIR} ${KUBECONFIG_DIR}
fi

REGION=$(gcloud config get-value compute/region)
ZONE=$(gcloud config get-value compute/zone)

export KUBECONFIG=./.kubeconfig:~/.kube/config