# Set defaults below

NUM_WORKERS=5  # Max: 9 nodes
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

# Don't change below this line

if [[ ${0:-defaults.sh} != "defaults.sh" && ${0:-bash} != "bash" ]]; then
  set -o errexit
  set -o nounset
  set -o pipefail
fi

# Avoid setting using array index to it's compatible with Bash and Zsh
ALL_CONTROLLERS=()
for (( i=0; i<3; i++ )); do
  if [[ $i -eq 0 ]]; then
    ALL_CONTROLLERS=(${CONTROLLER_PREFIX}-$i)
  else
    ALL_CONTROLLERS=("${ALL_CONTROLLERS[@]:-}" ${CONTROLLER_PREFIX}-$i)
  fi
done
ALL_WORKERS=()
for (( i=0; i<$NUM_WORKERS; i++ )); do
  if [[ $i -eq 0 ]]; then
    ALL_WORKERS=(${WORKER_PREFIX}-$i)
  else
    ALL_WORKERS=("${ALL_WORKERS[@]:-}" ${WORKER_PREFIX}-$i)
  fi
done

if [[ ! -z ${BASE_DIR:-} ]]; then
  CONFIG_DIR=${BASE_DIR}/config
  CERTS_DIR=${BASE_DIR}/certs
  KUBECONFIG_DIR=${BASE_DIR}/kubeconfig
  mkdir -p ${CONFIG_DIR} ${CERTS_DIR} ${KUBECONFIG_DIR}
fi

REGION=$(gcloud config get-value compute/region)
ZONE=$(gcloud config get-value compute/zone)

export KUBECONFIG=./.kubeconfig:~/.kube/config

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

function private_ip() {
  local hostname=$1
  if [[ $hostname == "$WORKER_PREFIX"* ]]; then
    echo "10.240.0.2${hostname##*-}"
  elif [[ $hostname == "$CONTROLLER_PREFIX"* ]]; then
    echo "10.240.0.1${hostname##*-}"
  else
    echo "ERROR: Unknown hostname $hostname"
    exit 1
  fi
}

function pod_cidr() {
  local hostname=$1
  if [[ $hostname == "$WORKER_PREFIX"* ]]; then
    echo "10.200.${hostname##*-}.0/24"
  elif [[ $hostname == "$CONTROLLER_PREFIX"* ]]; then
    echo "ERROR: Function undefined for controllers"
    exit 1
  else
    echo "ERROR: Unknown hostname $hostname"
    exit 1
  fi
}
