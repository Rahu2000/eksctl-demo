##############################################################
# CLUSTER AUTOSCALER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   charts: cluster-autoscaler v9.7.0
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_ROLE_NAME="AmazonEKS_Cluster_Autoscaler_Role"
export IAM_POLICY_NAME="AmazonEKS_Cluster_Autoscaler_Policy"
export CHART_VERSION="v9.7.0"
export NAMESPACE="kube-system"
export RELEASE_NAME="aws-cluster-autoscaler"
export SERVICE_ACCOUNT="aws-cluster-autoscaler"
export ENABBLE_PROMETHEUS_MONITORING="false"

source ../common/utils.sh

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}
  exit 0
fi

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR
cp ./templates/*.values.yaml /tmp/${DIR}/

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## Create a Policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://./templates/cluster-autoscaler-policy.json | jq -r .Policy.Arn)
fi

## Create a Role
ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")

##############################################################
# Install Cluster Autoscaler with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
## Add the autoscaler Helm repository
if [ -z "$(helm repo list | grep https://kubernetes.github.io/autoscaler)" ]; then
  helm repo add autoscaler https://kubernetes.github.io/autoscaler
fi
helm repo update

## Modifying variables
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s|IAM_ROLE_NAME|${ROLE_ARN}|g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i '' "s|CLUSTER_NAME|${CLUSTER_NAME}|g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i '' "s|RELEASE_NAME|${RELEASE_NAME}|g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i '' "s|ENABBLE_PROMETHEUS_MONITORING|${ENABBLE_PROMETHEUS_MONITORING}|g" /tmp/${DIR}/cluster-autoscaler.values.yaml
else
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's/\//\\//')
  sed -i.bak "s/IAM_ROLE_NAME/${ROLE_ARN}/g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i "s/CLUSTER_NAME/${CLUSTER_NAME}/g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i "s/RELEASE_NAME/${RELEASE_NAME}/g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" /tmp/${DIR}/cluster-autoscaler.values.yaml
  sed -i "s/ENABBLE_PROMETHEUS_MONITORING/${ENABBLE_PROMETHEUS_MONITORING}/g" /tmp/${DIR}/cluster-autoscaler.values.yaml
fi

## Install the cluster-autoscaler helm chart
helm upgrade --install \
  ${RELEASE_NAME} autoscaler/cluster-autoscaler \
  --version=${CHART_VERSION} \
  --namespace "$NAMESPACE" \
  -f /tmp/${DIR}/cluster-autoscaler.values.yaml \
  --wait