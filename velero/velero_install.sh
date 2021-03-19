##############################################################
# VELERO INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
##############################################################
#!/bin/bash
set -x
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazoneEKS_S3_Policy_For_Velero"
export IAM_ROLE_NAME="AmazoneEKS_S3_Role_For_Velero"
export APP_VERSION="v1.1.0"
export VELERO_BUCKET_PREFIX="velero-$CLUSTER_NAME"
export SNAPSHOT_BUCKET="snapshot"
export BACKUP_BUCKET="backup"
export SERVICE_ACCOUNT="velero"
export NAMESPACE="velero"
export CHART_VERSION="2.15.0"
export REGION="ap-northeast-2"
export CLEANUP_CRDS="true" # Caution: Cleaning up CRDs will delete the BackupStorageLocation and VolumeSnapshotLocation instances, which would have to be reconfigured.

source ../common/utils.sh

##############################################################
# Bucket Create
##############################################################
BACKUP_BUCKET_NAME="${VELERO_BUCKET_PREFIX}-${BACKUP_BUCKET}"
SNAPSHOT_BUCKET_NAME=$BACKUP_BUCKET_NAME

if [[ -z $(aws s3 ls --region "$REGION" 2>/dev/null | grep "${BACKUP_BUCKET_NAME}") ]]; then
  aws s3 mb "s3://${BACKUP_BUCKET_NAME}" --region "$REGION"
fi

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|VELERO_BUCKET_PREFIX|${VELERO_BUCKET_PREFIX}|g" ./templates/velero-policy.json
else
  sed -i.bak "s/VELERO_BUCKET_PREFIX/${VELERO_BUCKET_PREFIX}/g" ./templates/velero-policy.json
fi

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://./templates/velero-policy.json | jq -r .Policy.Arn)
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")

##############################################################
# Install Velero with Helm
##############################################################
## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://vmware-tanzu.github.io/helm-charts)" ]; then
  helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/velero.values.yaml
  sed -i '' "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/velero.values.yaml
  sed -i '' "s|APP_VERSION|${APP_VERSION}|g" ./templates/velero.values.yaml
  sed -i '' "s|BACKUP_BUCKET_NAME|${BACKUP_BUCKET_NAME}|g" ./templates/velero.values.yaml
  sed -i '' "s|SNAPSHOT_BUCKET_NAME|${SNAPSHOT_BUCKET_NAME}|g" ./templates/velero.values.yaml
  sed -i '' "s|CLUSTER_NAME|${CLUSTER_NAME}|g" ./templates/velero.values.yaml
  sed -i '' "s|REGION|${REGION}|g" ./templates/velero.values.yaml
  sed -i '' "s|CLEANUP_CRDS|${CLEANUP_CRDS}|g" ./templates/velero.values.yaml
else
  sed -i.bak "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/velero.values.yaml
  sed -i "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/velero.values.yaml
  sed -i "s/APP_VERSION/${APP_VERSION}/g" ./templates/velero.values.yaml
  sed -i "s/BACKUP_BUCKET_NAME/${BACKUP_BUCKET_NAME}/g" ./templates/velero.values.yaml
  sed -i "s/SNAPSHOT_BUCKET_NAME/${SNAPSHOT_BUCKET_NAME}/g" ./templates/velero.values.yaml
  sed -i "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ./templates/velero.values.yaml
  sed -i "s/REGION/${REGION}/g" ./templates/velero.values.yaml
  sed -i "s/CLEANUP_CRDS/${CLEANUP_CRDS}/g" ./templates/velero.values.yaml
fi

helm upgrade --install velero \
  vmware-tanzu/velero \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  --create-namespace \
  -f ./templates/velero.values.yaml \
  --wait