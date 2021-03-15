##############################################################
# AWS FSX STORAGECLASS CREATOR
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   fsx-csi v0.4.0
##############################################################
#!/bin/bash

export FSX_SC_NAME="fsx-private-a" # example: prefix-[public|private]-az
export SUBNET_ID="subnet-05df3c1294978641b"
export SECURITY_GROUP_ID="sg-021bf003b3c82d636"
export S3_BUCKET_NAME="fsx-$(uuidgen | awk '{print tolower($0)}')"
export SCRACH_TYPE="SCRATCH_2"

# Create a S3 bucket
if [[ -z $(aws s3 ls 2>/dev/null | grep $S3_BUCKET_NAME) ]]; then
  aws s3 mb s3://$S3_BUCKET_NAME
fi

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|FSX_SC_NAME|${FSX_SC_NAME}|g" ./templates/fsx-storageclass.yaml
  sed -i '' "s|SUBNET_ID|${SUBNET_ID}|g" ./templates/fsx-storageclass.yaml
  sed -i '' "s|SECURITY_GROUP_ID|${SECURITY_GROUP_ID}|g" ./templates/fsx-storageclass.yaml
  sed -i '' "s|S3_BUCKET_NAME|${S3_BUCKET_NAME}|g" ./templates/fsx-storageclass.yaml
  sed -i '' "s|SCRACH_TYPE|${SCRACH_TYPE}|g" ./templates/fsx-storageclass.yaml
else
  sed -i.bak "s|FSX_SC_NAME|${FSX_SC_NAME}|g" ./templates/fsx-storageclass.yaml
  sed -i '' "s/SUBNET_ID/${SUBNET_ID}/g" ./templates/fsx-storageclass.yaml
  sed -i '' "s/SECURITY_GROUP_ID/${SECURITY_GROUP_ID}/g" ./templates/fsx-storageclass.yaml
  sed -i '' "s/S3_BUCKET_NAME/${S3_BUCKET_NAME}/g" ./templates/fsx-storageclass.yaml
  sed -i '' "s/SCRACH_TYPE/${SCRACH_TYPE}/g" ./templates/fsx-storageclass.yaml
fi

# Create fsx storageclass
kubectl apply -f ./templates/fsx-storageclass.yaml