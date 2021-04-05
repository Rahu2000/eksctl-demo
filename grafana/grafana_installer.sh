##############################################################
# GRAFANA INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: bitnami/grafana-operator (0.6.4)
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_Grafana_CloudWatch_Policy"
export IAM_ROLE_NAME="AmazonEKS_Grafana_CloudWatch_Role"
export SERVICE_ACCOUNT="grafana-operator"
export NAMESPACE="grafana"
export CHART_VERSION="0.6.4"
export REGION="ap-northeast-2"
export RELEASE_NAME="grafana"
export CLOUDWATCH_ENABLED="true" # [true|false]
export PROMETHEUS_NAMESPACE="prometheus"

source ../common/utils.sh

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

  kubectl delete ns ${NAMESPACE}

  kubectl delete --ignore-not-found customresourcedefinitions\
    grafanadashboards.integreatly.org\
    grafanadatasources.integreatly.org\
    grafanas.integreatly.org
  exit 0
fi

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# CloudWatch Role for Grafana Dashboard
##############################################################
if [ 'true' == "$CLOUDWATCH_ENABLED" ]; then

  NODEGROUP_ROLE_ARN=""
  ROLES=$(aws iam list-roles | grep "$CLUSTER_NAME-nodegroup" | grep Arn | awk -F ' ' ' {print $2} ')
  STR=$(arrayToString "$ROLES")

  if [ -n "$STR" ]; then
    if [[ ',' == "${STR: -1}" ]]; then
      if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
        NODEGROUP_ROLE_ARN=[${STR:0:$((${#STR} - 0 - 1))}]
      else
        NODEGROUP_ROLE_ARN=[${STR::-1}]
      fi
    else
      NODEGROUP_ROLE_ARN=[$STR]
    fi
  fi

  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i.bak "s|NODEGROUP_ROLE_ARN|${NODEGROUP_ROLE_ARN}|g" ./templates/trust_relationship.yaml
  else
    NODEGROUP_ROLE_ARN=$(echo ${NODEGROUP_ROLE_ARN} | sed 's|\/|\\/|')
    sed -i.bak "s/NODEGROUP_ROLE_ARN/${NODEGROUP_ROLE_ARN}/g" ./templates/trust_relationship.yaml
  fi

  IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
  if [ -z "$IAM_POLICY_ARN" ]; then
    IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://templates/cloudwatch-policy.json | jq -r .Policy.Arn)
  fi

  ## Create a Role
  IAM_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" 2>/dev/null | jq -r '.Role.Arn' 2>/dev/null)
  if [ -z "$IAM_ROLE_ARN" ]; then

    IAM_ROLE_ARN=$(aws iam create-role --role-name "$IAM_ROLE_NAME" --assume-role-policy-document file://./templates/trust_relationship.yaml | jq -r '.Role.Arn')

    while true;
    do
      role=$(aws iam get-role --role-name "$IAM_ROLE_NAME" 2> /dev/null)
      if [ -n "$role" ]; then
        aws iam attach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn="$IAM_POLICY_ARN"
        break;
      fi
      sleep 1
    done
  fi

  echo "CloudWatch Role Arn is $IAM_ROLE_ARN"
fi

##############################################################
# Install Grafana with Helm
##############################################################
## Add the Bitnami Helm repository
if [ -z "$(helm repo list | grep https://charts.bitnami.com/bitnami)" ]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|BIND_NAMESPACE|${PROMETHEUS_NAMESPACE},${NAMESPACE}|g" ./templates/grafana.values.yaml
else
  sed -i.bak "s/BIND_NAMESPACE/${PROMETHEUS_NAMESPACE},${NAMESPACE}/g" ./templates/grafana.values.yaml
fi

helm upgrade --install ${RELEASE_NAME} \
  bitnami/grafana-operator \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  --create-namespace \
  -f ./templates/grafana.values.yaml \
  --wait
