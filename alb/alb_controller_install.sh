##############################################################
# AWS LOAD BALANCER CONTROLLER INSTALLER
#
# Required tools
# - helm v3+
# - yq 2.12.0+
# - jq 1.6+
# - curl
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   cert-manager v1.0.2
#   aws-load-balancer-controller v2.1.3
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AWSLoadBalancerControllerPolicy"
export CERT_MANGER_VERSION="v1.0.2"
export ALB_CONTROLLER_VERSION="v2.1.3"
export ALB_CONTROLLER_FILE="v2_1_3"
export REGION="ap-northeast-2"

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# IAM Policy for aws-load-balancer-controller ServiceAccount
##############################################################
## download a latest policy for Aws Load Balancer controller from kubernetes-sigs
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/"${ALB_CONTROLLER_VERSION}"/docs/install/iam_policy.json

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://iam_policy.json | jq -r .Policy.Arn)
fi

##############################################################
# Install the cert-manager
##############################################################
## Apply priority class
kubectl apply -f ./tempates/operator.priority.class.yaml

## Install the cert-manager CRD
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/"${CERT_MANGER_VERSION}"/cert-manager.crds.yaml

## Add the Jetstack Helm repository
if [ -z "$(helm repo list | grep https://charts.jetstack.io)" ]; then
  helm repo add jetstack https://charts.jetstack.io
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s|IAM_ROLE_NAME|${ROLE_ARN}|g" ./templates/cert-manager.value.yaml
  sed -i '' "s|CERT_MANGER_VERSION|${CERT_MANGER_VERSION}|g" ./templates/cert-manager.value.yaml
else
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's/\//\\//')
  sed -i.bak "s/IAM_ROLE_NAME/${ROLE_ARN}/g" ./templates/cert-manager.value.yaml
  sed -i '' "s/CERT_MANGER_VERSION/${CERT_MANGER_VERSION}/g" ./templates/cert-manager.value.yaml
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
# Install the aws-load-balancer-controller
##############################################################
## Update serviceaccount
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=${IAM_POLICY_ARN} \
  --override-existing-serviceaccounts \
  --approve

sleep 10

## Manifest download
curl -o "${ALB_CONTROLLER_FILE}_full.yaml" https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/"${ALB_CONTROLLER_VERSION}"/docs/install/"${ALB_CONTROLLER_FILE}"_full.yaml

## Remove 'ServiceAccount Resource definition' from downloaded file
START_LINE=$(grep -n "^kind: ServiceAccount" "${ALB_CONTROLLER_FILE}"_full.yaml|awk -F ':' ' { print$1 } ')
let "START_LINE-=1"
END_LINE=0
for line in $(grep -n "^---$" "${ALB_CONTROLLER_FILE}"_full.yaml)
do
  number=$(echo "$line" | awk -F ':' ' { print$1 } ')
  if [ $number -gt $START_LINE ]; then
    END_LINE=$number
    break;
  fi
done

## Remove line
sed -i.bak -e "${START_LINE},${END_LINE}d;" "${ALB_CONTROLLER_FILE}"_full.yaml

# Modify cluster name and resource.requests.memory (to avoid OOM)
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i '' "s|your-cluster-name|${CLUSTER_NAME}|g" "${ALB_CONTROLLER_FILE}"_full.yaml
  sed -i '' "s|200Mi|500Mi|g" "${ALB_CONTROLLER_FILE}"_full.yaml
else
  sed -i '' "s/your-cluster-name/${CLUSTER_NAME}/g" "${ALB_CONTROLLER_FILE}"_full.yaml
  sed -i '' "s/200Mi/500Mi/g" "${ALB_CONTROLLER_FILE}"_full.yaml
fi

# # Confirm cert-manager.io's version
# if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
#   sed -i '' "s|cert-manager.io\/v1alpha2|cert-manager.io\/v1|g" "${ALB_CONTROLLER_FILE}"_full.yaml
# else
#   sed -i '' "s/cert-manager.io\/v1alpha2|cert-manager.io\/v1/g" "${ALB_CONTROLLER_FILE}"_full.yaml
# fi

## install aws-load-balance-controller
kubectl apply --validate=false -f "${ALB_CONTROLLER_FILE}"_full.yaml

## Patch spec
ARG1="--aws-vpc-id=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION | jq -r .cluster.resourcesVpcConfig.vpcId)"
ARG2="--aws-region=$REGION"

## add affinity, tolerantions, priorityClassName and apply
## NOTICE: you should be modify some values in spec.yaml
## - affinity
## - tolerations
SPEC=$(cat ./templates/spec.yaml | yq | jq -r -c )

## Patch deployments/aws-load-balancer-controller
kubectl get deployments/aws-load-balancer-controller -n kube-system -ojson | jq --arg vpc "${ARG1}" --arg region "${ARG2}" '.spec.template.spec.containers[0].args |= . + [$vpc,$region]' | jq --argjson spec "${SPEC}" '.spec.template.spec +=  $spec' | jq '.spec.template.metadata +=  {"annotations": {"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}' | kubectl apply -f -

## Add PodDisruptionBudget
kubectl apply -f ./templates/alb_controller_pdb.yaml
