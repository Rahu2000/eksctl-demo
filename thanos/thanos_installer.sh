##############################################################
# THANOS INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: bitnami/thanos (3.15.1)
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_Prometheus_Thanos_Policy"
export IAM_ROLE_NAME="AmazonEKS_Thanos_Role"
export SERVICE_ACCOUNT="thanos"
export NAMESPACE="monitoring"
export CHART_VERSION="3.15.1"
export THANOS_SECRET_NAME="thanos-objstore-config"
export RELEASE_NAME="thanos"
export PROMETHEUS_NAMESPACE="monitoring"

source ../common/utils.sh

IAM_ROLE_ARN=""
IAM_POLICY_ARN=""

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

  if [ $PROMETHEUS_NAMESPACE != $NAMESPACE ]; then
    kubectl delete ns ${NAMESPACE}
  fi

  exit 0
fi

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

echo 'Creating Roles ...'

## Search for a policy by name
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname ${IAM_POLICY_NAME} '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')

if [ -z "$IAM_POLICY_ARN" ]; then
  echo "Policy: $IAM_POLICY_NAME is not found."
  exit 1
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")

# Create a Service account
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/thanos-service-account.yaml
  sed -i '' "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/thanos-service-account.yaml
  sed -i '' "s|NAMESPACE|${NAMESPACE}|g" ./templates/thanos-service-account.yaml
  sed -i '' "s|RELEASE_NAME|${RELEASE_NAME}|g" ./templates/thanos-service-account.yaml
  sed -i '' "s|CHART_VERSION|${CHART_VERSION}|g" ./templates/thanos-service-account.yaml
else
  sed -i.bak "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/thanos-service-account.yaml
  IAM_ROLE_ARN=$(echo ${IAM_ROLE_ARN} | sed 's|\/|\\/|')
  sed -i "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/thanos-service-account.yaml
  sed -i "s/NAMESPACE/${NAMESPACE}/g" ./templates/thanos-service-account.yaml
  sed -i "s/RELEASE_NAME/${RELEASE_NAME}/g" ./templates/thanos-service-account.yaml
  sed -i "s/CHART_VERSION/${CHART_VERSION}/g" ./templates/thanos-service-account.yaml
fi

##############################################################
# Prerequisites
#   - Namespace
#   - Object store secret
#   - ServiceAccount
##############################################################
if [ $PROMETHEUS_NAMESPACE != $NAMESPACE ]; then
  kubectl create ns $NAMESPACE
  kubectl get secret "$THANOS_SECRET_NAME" --namespace "$NAMESPACE" || kubectl get secret "$THANOS_SECRET_NAME" --namespace="$PROMETHEUS_NAMESPACE" -oyaml | grep -v '^\s*namespace:\s' | kubectl apply --namespace="$NAMESPACE" -f -
fi

kubectl apply -f ./templates/thanos-service-account.yaml
##############################################################
# Install Thanos with Helm
##############################################################
## Add the Bitnami Helm repository
if [ -z "$(helm repo list | grep https://charts.bitnami.com/bitnami)" ]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

ALERT_MANAGER_URL="$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} | awk -F ' ' ' {print $1} ' | grep alertmanager$).${PROMETHEUS_NAMESPACE}.svc.cluster.local"
PROMETHEUS_SERVICE=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} | awk -F ' ' ' {print $1} ' | grep prometheus$)
THANOS_SIDECAR_SERVICE=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} | awk -F ' ' ' {print $1} ' | grep thanos$)

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|THANOS_SECRET_NAME|${THANOS_SECRET_NAME}|g" ./templates/thanos.values.yaml
  sed -i '' "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/thanos.values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/thanos.values.yaml
  sed -i '' "s|ALERT_MANAGER_URL|${ALERT_MANAGER_URL}|g" ./templates/thanos.values.yaml
  sed -i '' "s|PROMETHEUS_SERVICE|${PROMETHEUS_SERVICE}|g" ./templates/thanos.values.yaml
  sed -i '' "s|THANOS_SIDECAR_SERVICE|${THANOS_SIDECAR_SERVICE}|g" ./templates/thanos.values.yaml
  sed -i '' "s|PROMETHEUS_NAMESPACE|${PROMETHEUS_NAMESPACE}|g" ./templates/thanos.values.yaml
else
  sed -i.bak "s/THANOS_SECRET_NAME/${THANOS_SECRET_NAME}/g" ./templates/thanos.values.yaml
  sed -i "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/thanos.values.yaml
  sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/thanos.values.yaml
  sed -i "s/ALERT_MANAGER_URL/${ALERT_MANAGER_URL}/g" ./templates/thanos.values.yaml
  sed -i "s/PROMETHEUS_SERVICE/${PROMETHEUS_SERVICE}/g" ./templates/thanos.values.yaml
  sed -i "s/THANOS_SIDECAR_SERVICE/${THANOS_SIDECAR_SERVICE}/g" ./templates/thanos.values.yaml
  sed -i "s/PROMETHEUS_NAMESPACE/${PROMETHEUS_NAMESPACE}/g" ./templates/thanos.values.yaml
fi

helm upgrade --install ${RELEASE_NAME} \
  bitnami/thanos \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/thanos.values.yaml \
  --wait