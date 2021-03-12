##############################################################
# AWS FSX CSI DRIVER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   aws-fsx-csi v0.4.0
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="Amazon_FSx_Lustre_CSI_Driver"
export NAMESPACE="kube-system"
export SERVICE_ACCOUNT="fsx-csi-controller"
export CHART_VERSION="v0.1.0"
export REGION="ap-northeast-2"

source ../common/utils.sh

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://templates/fsx-csi-driver.json | jq -r .Policy.Arn)
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "Amazon_FSx_Lustre_CSI_Driver_Role" "$IAM_POLICY_ARN")

## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://https://kubernetes-sigs.github.io/aws-fsx-csi-driver)" ]; then
  helm repo add aws-fsx-csi-driver https://kubernetes-sigs.github.io/aws-fsx-csi-driver
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/fsx-csi-driver.values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/fsx-csi-driver.values.yaml
else
  sed -i.bak "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/fsx-csi-driver.values.yaml
  sed -i '' "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/fsx-csi-driver.values.yaml
fi

helm upgrade --install aws-fsx-csi-driver \
  aws-fsx-csi-driver/aws-fsx-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/fsx-csi-driver.values.yaml \
  --wait

CONTROLLER_SPEC=$(cat ./templates/controller-additional-spec.yaml | yq | jq -r -c )

## Patch deployments/aws-fsx-csi-driver-controller
kubectl get deployments/aws-fsx-csi-driver-controller -n kube-system -ojson | jq --argjson spec "${CONTROLLER_SPEC}" '.spec.template.spec +=  $spec' | kubectl apply -f -

NODE_SPEC=$(cat ./templates/node-additional-spec.yaml | yq | jq -r -c )

## Patch daemonsets/aws-load-balancer-controller
kubectl get deployments/aws-fsx-csi-driver-daemonset -n kube-system -ojson | jq --argjson spec "${NODE_SPEC}" '.spec.template.spec +=  $spec' | kubectl apply -f -
