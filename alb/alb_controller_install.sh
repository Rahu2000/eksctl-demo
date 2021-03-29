##############################################################
# AWS LOAD BALANCER CONTROLLER INSTALLER
#
# Required tools
# - helm v3+
# - yq 2.12.0+
# - jq 1.6+
# - curl
# - kubectl 1.16+
# - gnu-sed
#
# Tested version
#   EKS v1.19
#   cert-manager v1.0.2
#   aws-load-balancer-controller v2.1.3
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_Load_Balancer_Controller_Policy"
export IAM_ROLE_NAME="AmazonEKS_Load_Balancer_Controller_Role"
export CERT_MANGER_VERSION="v1.0.2"
export ALB_CONTROLLER_VERSION="v2.1.3"
export ALB_CONTROLLER_FILE="v2_1_3"
export SERVICE_ACCOUNT="aws-load-balancer-controller"
export NAMESPACE="kube-system"
export REGION="ap-northeast-2"

source ../common/utils.sh

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# Install the cert-manager
##############################################################
## Install the cert-manager CRD
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/"${CERT_MANGER_VERSION}"/cert-manager.crds.yaml

## Add the Jetstack Helm repository
if [ -z "$(helm repo list | grep https://charts.jetstack.io)" ]; then
  helm repo add jetstack https://charts.jetstack.io
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|CERT_MANGER_VERSION|${CERT_MANGER_VERSION}|g" ./templates/cert-manager.value.yaml
else
  sed -i.bak "s/CERT_MANGER_VERSION/${CERT_MANGER_VERSION}/g" ./templates/cert-manager.value.yaml
fi

## Install the cert-manager helm chart
helm upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version "${CERT_MANGER_VERSION}" \
  --create-namespace \
  -f ./templates/cert-manager.value.yaml \
  --wait

##############################################################
# Create IAM Role for a aws-load-balancer-controller ServiceAccount
##############################################################
## download a latest policy for Aws Load Balancer controller from kubernetes-sigs
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/"${ALB_CONTROLLER_VERSION}"/docs/install/iam_policy.json

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://iam_policy.json | jq -r .Policy.Arn)
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")

##############################################################
# Install the aws-load-balancer-controller
##############################################################
## Manifest download
curl -o "${ALB_CONTROLLER_FILE}_full.yaml" https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/"${ALB_CONTROLLER_VERSION}"/docs/install/"${ALB_CONTROLLER_FILE}_full.yaml"

SA_LINE_NUM=$(grep -n "^kind: ServiceAccount" "${ALB_CONTROLLER_FILE}_full.yaml"|awk -F ':' ' { print$1 } ')
let "SA_LINE_NUM+=1"

# Modify cluster name and resource.requests.memory (to avoid OOM)
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  gsed -i "${SA_LINE_NUM} a XXXXeks.amazonaws.com/role-arn: ${IAM_ROLE_ARN}" "${ALB_CONTROLLER_FILE}_full.yaml"
  gsed -i "${SA_LINE_NUM} a XXannotations:" "${ALB_CONTROLLER_FILE}_full.yaml"
  gsed -i 's/XX/  /g' "${ALB_CONTROLLER_FILE}_full.yaml"
  sed -i '' "s|your-cluster-name|${CLUSTER_NAME}|g" "${ALB_CONTROLLER_FILE}_full.yaml"
  # sed -i '' "s|200Mi|500Mi|g" "${ALB_CONTROLLER_FILE}_full.yaml"
else
  sed -i "${SA_LINE_NUM} a XXXXeks.amazonaws.com/role-arn: ${IAM_ROLE_ARN}" "${ALB_CONTROLLER_FILE}_full.yaml"
  sed -i "${SA_LINE_NUM} a XXannotations:" "${ALB_CONTROLLER_FILE}_full.yaml"
  sed -i 's/XX/  /g' "${ALB_CONTROLLER_FILE}_full.yaml"
  sed -i "s/your-cluster-name/${CLUSTER_NAME}/g" "${ALB_CONTROLLER_FILE}_full.yaml"
  # sed -i '' "s/200Mi/500Mi/g" "${ALB_CONTROLLER_FILE}_full.yaml"
fi

## install aws-load-balance-controller
kubectl apply --validate=false -f "${ALB_CONTROLLER_FILE}_full.yaml"

## Patch spec
ARG1="--aws-vpc-id=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION | jq -r .cluster.resourcesVpcConfig.vpcId)"
ARG2="--aws-region=$REGION"

## add affinity, tolerantions, priorityClassName and apply
## NOTICE: you should be modify some values in spec.yaml
## - affinity
## - tolerations
SPEC=$(cat ./templates/spec.yaml | yq | jq -r -c )

## Patch deployments/aws-load-balancer-controller
kubectl get deployments/aws-load-balancer-controller -n kube-system -ojson | jq --arg vpc "${ARG1}" --arg region "${ARG2}" '.spec.template.spec.containers[0].args |= . + [$vpc,$region]' | jq --argjson spec "${SPEC}" '.spec.template.spec +=  $spec' | kubectl apply -f -

## Add PodDisruptionBudget
kubectl apply -f ./templates/alb-controller-pdb.yaml
