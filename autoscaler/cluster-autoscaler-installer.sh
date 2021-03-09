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
#   cluster-autoscaler v1.19.1
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_ROLE_NAME="AmazonEKSClusterAutoscalerRole"
export IAM_POLICY_NAME="AmazonEKSClusterAutoscalerPolicy"
export CA_FILE="cluster-autoscaler-autodiscover"
export CA_VERSION="v1.19.1"
export NAMESPACE="kube-system"
export RELEASE_NAME="aws-cluster-autoscaler"
export IAM_ROLE_DESCRIPTION=$IAM_ROLE_NAME

## Function
function generateTrustFile {
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  OIDC_PROVIDER=$(aws eks describe-cluster --name $1 --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

  read -r -d '' TRUST_RELATIONSHIP <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "${OIDC_PROVIDER}:sub": "system:serviceaccount:$2:$3",
            "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  }
EOF
  echo "${TRUST_RELATIONSHIP}" > trust.json
}

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

## Create a Policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://./templates/cluster-autoscaler-policy.json | jq -r .Policy.Arn)
fi

## Create a Role
ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null | jq -r '.Role.Arn' 2>/dev/null)
if [ -z "$ROLE_ARN" ]; then
  generateTrustFile $CLUSTER_NAME $NAMESPACE $RELEASE_NAME
  ROLE_ARN=$(aws iam create-role --role-name ${IAM_ROLE_NAME} --assume-role-policy-document file://trust.json --description "${IAM_ROLE_DESCRIPTION}" | jq -r '.Role.Arn')

  while true;
  do
      role=$(aws iam get-role --role-name ${IAM_ROLE_NAME} 2> /dev/null)
      if [ -n "$role" ]; then
          aws iam attach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn=${IAM_POLICY_ARN}
          break;
      fi
      sleep 1
  done
fi

## Add the autoscaler Helm repository
if [ -z "$(helm repo list | grep https://kubernetes.github.io/autoscaler)" ]; then
  helm repo add autoscaler https://kubernetes.github.io/autoscaler
fi
helm repo update

## Modifying variables
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s|IAM_ROLE_NAME|${ROLE_ARN}|g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s|CLUSTER_NAME|${CLUSTER_NAME}|g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s|RELEASE_NAME|${RELEASE_NAME}|g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s|CA_VERSION|${CA_VERSION}|g" ./templates/cluster-autoscaler.values.yaml
else
  ROLE_ARN=$(echo ${ROLE_ARN} | sed 's/\//\\//')
  sed -i.bak "s/IAM_ROLE_NAME/${ROLE_ARN}/g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s/RELEASE_NAME/${RELEASE_NAME}/g" ./templates/cluster-autoscaler.values.yaml
  sed -i '' "s/CA_VERSION/${CA_VERSION}/g" ./templates/cluster-autoscaler.values.yaml
fi

## Install the cluster-autoscaler helm chart
helm upgrade --install \
  cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  -f ./templates/cluster-autoscaler.values.yaml \
  --wait