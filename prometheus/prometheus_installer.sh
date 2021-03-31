##############################################################
# PROMETHEUS INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: bitnami/kube-prometheus (4.2.1)
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_Prometheus_Thanos_Policy"
export IAM_ROLE_NAME="AmazonEKS_Prometheus_Thanos_Role"
export SERVICE_ACCOUNT="kube-prometheus.prometheus"
export NAMESPACE="monitoring"
export CHART_VERSION="4.2.1"
export REGION="ap-northeast-2"
export THANOS_SIDECAR="true" # [true|false]
export BUCKET_NAME="s3-prometheus-thanos"
export THANOS_SECRET_NAME="thanos-objstore-config"

source ../common/utils.sh

IAM_ROLE_ARN=""
IAM_POLICY_ARN=""

##############################################################
# Remove old CRDs
##############################################################
kubectl delete --ignore-not-found customresourcedefinitions\
  alertmanagerconfigs.monitoring.coreos.com\
  alertmanagers.monitoring.coreos.com\
  podmonitors.monitoring.coreos.com\
  probes.monitoring.coreos.com\
  prometheuses.monitoring.coreos.com\
  prometheusrules.monitoring.coreos.com\
  servicemonitors.monitoring.coreos.com\
  thanosrulers.monitoring.coreos.com

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
if [[ "true" == $THANOS_SIDECAR ]]; then

  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i.bak "s|BUCKET_NAME|${BUCKET_NAME}|g" ./templates/iam-policy.json
  else
    sed -i.bak "s/BUCKET_NAME/${BUCKET_NAME}/g" ./templates/iam-policy.json
  fi

  ## Search for a policy by name
  IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')

  ## create a policy
  if [ -z "$IAM_POLICY_ARN" ]; then
    IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://./templates/iam-policy.json | jq -r .Policy.Arn)
  fi

  IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")
else
  THANOS_SIDECAR="false"
fi

##############################################################
# Create Thanos Secret
##############################################################
kubectl create ns $NAMESPACE

if [[ "true" == $THANOS_SIDECAR ]]; then
  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i.bak "s|BUCKET_NAME|${BUCKET_NAME}|g" ./templates/thanos-config.yaml
    sed -i '' "s|REGION|${REGION}|g" ./templates/thanos-config.yaml
  else
    sed -i.bak "s/BUCKET_NAME/${BUCKET_NAME}/g" ./templates/thanos-config.yaml
    sed -i "s/REGION/${REGION}/g" ./templates/thanos-config.yaml
  fi

  kubectl create secret generic "$THANOS_SECRET_NAME" \
  --from-file=objstore.yml=./templates/thanos-config.yaml \
  --namespace $NAMESPACE
fi

##############################################################
# Install AWS EBS CSI DRIVER with Helm
##############################################################
## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://charts.bitnami.com/bitnami)" ]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/prometheus.values.yaml
  sed -i '' "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" ./templates/prometheus.values.yaml
  sed -i '' "s|THANOS_SIDECAR|${THANOS_SIDECAR}|g" ./templates/prometheus.values.yaml
  sed -i '' "s|THANOS_SECRET_NAME|${THANOS_SECRET_NAME}|g" ./templates/prometheus.values.yaml
else
  sed -i.bak "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/prometheus.values.yaml
  IAM_ROLE_ARN=$(echo ${IAM_ROLE_ARN} | sed 's|\/|\\/|')
  sed -i "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" ./templates/prometheus.values.yaml
  sed -i "s/THANOS_SIDECAR/${THANOS_SIDECAR}/g" ./templates/prometheus.values.yaml
  sed -i "s/THANOS_SECRET_NAME/${THANOS_SECRET_NAME}/g" ./templates/prometheus.values.yaml
fi

helm upgrade --install prometheus \
  bitnami/kube-prometheus \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/prometheus.values.yaml \
  --wait
