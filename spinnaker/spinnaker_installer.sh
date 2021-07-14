##############################################################
# SPINNAKER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
# - hal
#
# Tested version
#   EKS v1.19
#
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export FRONT50_IAM_POLICY_NAME="AmazonEKS_S3_Spinnaker_front50_Policy"
export FRONT50_IAM_ROLE_NAME="AmazonEKS_S3_Spinnaker_front50_Role"
export FRONT50_SERVICE_ACCOUNT="spin-front50"

# export CLOUDDRIVER_IAM_ROLE_ARN="arn:aws:iam::497950399009:role/SpinnakerAuthRole"
export CLOUDDRIVER_SERVICE_ACCOUNT="spin-clouddriver"
export ROSCO_SERVICE_ACCOUNT="spin-rosco"

export NAMESPACE="spinnaker"
export SPINNAKER_VERSION="1.24.4"
export REGION="ap-northeast-2"
export BUCKET_NAME="s3-spinnaker-apne-2"
export CONTEXT="eks-spinnaker"
export DEFAULT_SERVICE_ACCOUNT="spinnaker-service-account"

source ../common/utils.sh

FRONT50_IAM_ROLE_ARN=""
FRONT50_IAM_POLICY_ARN=""

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  hal deploy clean
  kubectl delete ns $NAMESPACE
fi

##############################################################
# Create IAM Roles and ServiceAccounts
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

echo "create role for front50..."

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|BUCKET_NAME|${BUCKET_NAME}|g" ./templates/front50-s3-policy.json
else
  sed -i.bak "s/BUCKET_NAME/${BUCKET_NAME}/g" ./templates/front50-s3-policy.json
fi

## Search for a policy by name
FRONT50_IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $FRONT50_IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')

## create a policy
if [ -z "$FRONT50_IAM_POLICY_ARN" ]; then
  FRONT50_IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${FRONT50_IAM_POLICY_NAME} --policy-document file://./templates/front50-s3-policy.json | jq -r .Policy.Arn)
fi

FRONT50_IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$FRONT50_SERVICE_ACCOUNT" "$FRONT50_IAM_ROLE_NAME" "$FRONT50_IAM_POLICY_ARN")

##############################################################
# Default Settings for Spinnkaer
##############################################################
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --alias $CONTEXT
kubectl config use-context $CONTEXT
kubectl apply --context $CONTEXT -f https://www.spinnaker.io/downloads/kubernetes/service-account.yml

kubectl apply --context $CONTEXT -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${FRONT50_SERVICE_ACCOUNT}
  namespace: $NAMESPACE
  annotations:
      eks.amazonaws.com/role-arn: ${FRONT50_IAM_ROLE_ARN}
EOF

kubectl apply --context $CONTEXT -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${CLOUDDRIVER_SERVICE_ACCOUNT}
  namespace: $NAMESPACE
EOF

kubectl apply --context $CONTEXT -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${ROSCO_SERVICE_ACCOUNT}
  namespace: $NAMESPACE
EOF

TOKEN=$(kubectl get secret --context $CONTEXT \
   $(kubectl get serviceaccount $DEFAULT_SERVICE_ACCOUNT \
       --context $CONTEXT \
       -n spinnaker \
       -o jsonpath='{.secrets[0].name}') \
   -n spinnaker \
   -o jsonpath='{.data.token}' | base64 --decode)

kubectl config set-credentials ${CONTEXT}-token-user --token $TOKEN
kubectl config set-context $CONTEXT --user ${CONTEXT}-token-user
