##############################################################
# AWS EFS CSI DRIVER INSTALLER
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

export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_EFS_CSI_Driver_Policy"
export IAM_ROLE_NAME="AmazonEFS_EFS_CSI_Driver_Role"
export SERVICE_ACCOUNT="efs-csi-controller"
export NAMESPACE="kube-system"
export CHART_VERSION="v1.1.2"
export REGION="ap-northeast-2"
export CREATE_CONTROLLER="false" # [true|false]

source ../common/utils.sh

IAM_ROLE_ARN=""
IAM_POLICY_ARN=""

if [[ "true" == $CREATE_CONTROLLER ]]; then
  ##############################################################
  # Create IAM Role and ServiceAccount
  ##############################################################
  ## download a latest policy for EFS CSI controller from kubernetes-sigs
  curl -sSL -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json

  ## Search for a policy by name
  IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')

  ## create a policy
  if [ -z "$IAM_POLICY_ARN" ]; then
    IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://iam-policy.json | jq -r .Policy.Arn)
  fi

  IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")
else
  CREATE_CONTROLLER="false"
fi
##############################################################
# Install AWS EBS CSI DRIVER with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://kubernetes-sigs.github.io/aws-efs-csi-driver)" ]; then
  helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|CREATE_CONTROLLER|${CREATE_CONTROLLER}|g" ./templates/efs-csi-driver.values.yaml
  if [[ "true" == $CREATE_CONTROLLER ]]; then
    sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/efs-csi-driver.values.yaml
    sed -i '' "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/efs-csi-driver.values.yaml
  fi
else
  sed -i.bak "s/CREATE_CONTROLLER/${CREATE_CONTROLLER}/g" ./templates/efs-csi-driver.values.yaml
  if [[ "true" == $CREATE_CONTROLLER ]]; then
    sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/efs-csi-driver.values.yaml
    sed -i "s/IAM_ROLE_ARN|${IAM_ROLE_ARN}/g" ./templates/efs-csi-driver.values.yaml
  fi
fi

helm upgrade --install aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/efs-csi-driver.values.yaml \
  --wait

if [[ "true" == $CREATE_CONTROLLER ]]; then
  ##############################################################
  ## Create a PodDisruptionBudget
  ##############################################################
  kubectl apply -f ./templates/efs-csi-controller-pdb.yaml
fi