##############################################################
# EXTERNAL DNS INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
# - EKS v1.19
#   chart: bitnami/external-dns/5.0.3 (0.8.0)
# - EKS v1.21
#   chart: bitnami/external-dns/5.4.15 (0.10.1)
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_External_DNS_Route53_Policy"
export IAM_ROLE_NAME="AmazonEKS_External_DNS_Route53_Role"
export NAMESPACE="external-dns"
export SERVICE_ACCOUNT="external-dns"
export CHART_VERSION="5.4.15"
export REGION="ap-northeast-2"
export ZONETYPE="public"
export DOMAINS="eksdemo.tk"
export DNS_POLICY=sync # sync | upsert-only
export RELEASE_NAME="external-dns-${ZONETYPE}"

source ../common/utils.sh

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}
  kubectl delete ns ${NAMESPACE}

  exit 0
fi

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR
cp ./templates/*.yaml /tmp/${DIR}/
##############################################################
# Check Route53
##############################################################
HOSTZONEID="$(aws route53 list-hosted-zones-by-name --output json --dns-name "$DOMAINS." | jq -r '.HostedZones[0].Id' | awk -F '/' '{print $3}')"
if [ -z $HOSTZONEID ]; then
  echo "HostedZone is not found."
  exit 0
fi

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## create a policy
echo 'Create IAM Role and Service Account...'
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://templates/route53-policy.json | jq -r .Policy.Arn)
fi

IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SERVICE_ACCOUNT" "$IAM_ROLE_NAME" "$IAM_POLICY_ARN")
echo 'Done.'

##############################################################
# Install External-DNS with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

## Add bitnami charts repo
if [ -z "$(helm repo list | grep https://charts.bitnami.com/bitnami)" ]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|IAM_ROLE_ARN|${IAM_ROLE_ARN}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|REGION|${REGION}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|ZONETYPE|${ZONETYPE}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|DNS_POLICY|${DNS_POLICY}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|DOMAINS|${DOMAINS}|g" /tmp/${DIR}/external-dns-values.yaml
  sed -i '' "s|HOSTZONEID|${HOSTZONEID}|g" /tmp/${DIR}/external-dns-values.yaml
else
  IAM_ROLE_ARN=$(echo ${IAM_ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s/IAM_ROLE_ARN/${IAM_ROLE_ARN}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/REGION/${REGION}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/ZONETYPE/${ZONETYPE}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/DNS_POLICY/${DNS_POLICY}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/DOMAINS/${DOMAINS}/g" /tmp/${DIR}/external-dns-values.yaml
  sed -i "s/HOSTZONEID/${HOSTZONEID}/g" /tmp/${DIR}/external-dns-values.yaml
fi

helm upgrade --install ${RELEASE_NAME} \
  bitnami/external-dns \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f /tmp/${DIR}/external-dns-values.yaml \
  --create-namespace \
  --wait