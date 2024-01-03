#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

## The Encryption Key

logmsg "Generate an encryption key:"

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

## The Encryption Config File

logmsg "Create the encryption-config.yaml encryption config file:"

cat > ${CONFIG_DIR}/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

for instance in "${ALL_CONTROLLERS[@]}"; do
  logmsg "Copy the encryption-config.yaml encryption config file to controller instance: $instance"
  gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${CONFIG_DIR}/encryption-config.yaml ${instance}:~/config/
done
