##############################################################
# AWS FSX CSI DRIVER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - yq
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: aws-fsx-csi-driver/aws-fsx-csi-driver v0.1.0 (0.4.0)
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_FSx_Lustre_CSI_Driver_Policy"
export IAM_ROLE_NAME="AmazonEKS_FSx_Lustre_CSI_Driver_Role"
export NAMESPACE="kube-system"
export SERVICE_ACCOUNT="fsx-csi-controller"
export CHART_VERSION="v0.1.0"
export REGION="ap-northeast-2"

source ../common/utils.sh

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://templates/fsx-csi-driver-policy.json | jq -r .Policy.Arn)
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")

##############################################################
# Install AWS FSX CSI DRIVER with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://https://kubernetes-sigs.github.io/aws-fsx-csi-driver)" ]; then
  helm repo add aws-fsx-csi-driver https://kubernetes-sigs.github.io/aws-fsx-csi-driver
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/fsx-csi-driver.values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/fsx-csi-driver.values.yaml
else
  IAM_ROLE_ARN=$(echo ${IAM_ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/fsx-csi-driver.values.yaml
  sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/fsx-csi-driver.values.yaml
fi

helm upgrade --install aws-fsx-csi-driver \
  aws-fsx-csi-driver/aws-fsx-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/fsx-csi-driver.values.yaml \
  --wait

##############################################################
# Update Spec
# Notice: should be replace tolerations values
##############################################################
CONTROLLER_SPEC=$(cat ./templates/controller-additional-spec.yaml | yq | jq -r -c )

## Patch deployments/aws-fsx-csi-driver-controller
kubectl get deployments/aws-fsx-csi-driver-controller -n kube-system -ojson | jq --argjson spec "${CONTROLLER_SPEC}" '.spec.template.spec +=  $spec' | jq '.spec.template.spec.tolerations +=  [{"key":"operator","operator":"Equal","value":"true","effect":"NoSchedule"}]' | kubectl apply -f -

## Patch daemonsets/aws-fsx-csi-driver-daemonset
kubectl get daemonsets/aws-fsx-csi-driver-daemonset -n kube-system -ojson | jq '.spec.template.spec.tolerations +=  [{"key":"operator","operator":"Equal","value":"true","effect":"NoSchedule"}]' | jq '.spec.template.spec +=  {"priorityClassName":"system-node-critical"}' | kubectl apply -f -

##############################################################
# Create a FSX controller PodDisruptionBudget
##############################################################
kubectl apply -f ./templates/fsx-csi-controller-pdb.yaml