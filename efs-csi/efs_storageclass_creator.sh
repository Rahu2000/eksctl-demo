##############################################################
# AWS EFS STORAGE CLASS CREATOR
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: aws-efs-csi 1.1.2 (1.1.1)
##############################################################
#!/bin/bash

export STORAGE_CLASS_NAME="efs-sc"
export FILE_SYSTEM_ID="fs-92107410"

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|STORAGE_CLASS_NAME|${STORAGE_CLASS_NAME}|g" ./templates/efs-storage-class.yaml
  sed -i '' "s|FILE_SYSTEM_ID|${FILE_SYSTEM_ID}|g" ./templates/efs-storage-class.yaml
else
  sed -i.bak "s/STORAGE_CLASS_NAME/${STORAGE_CLASS_NAME}/g" ./templates/efs-storage-class.yaml
  sed -i "s/FILE_SYSTEM_ID/${FILE_SYSTEM_ID}/g" ./templates/efs-storage-class.yaml
fi