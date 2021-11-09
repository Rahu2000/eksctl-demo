##############################################################
# Gitlab INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Prerequisite
# - Domain (with ACM)
# - Route53 (Hosted Zone)
# - External-dns (Provider: aws)
# - aws-load-balance-controller (when use nlb/alb)
#
# Tested version
# - EKS v1.19
#   gitlab/gitlab 4.10.2
# - EKS v1.21
#   gitlab/gitlab 5.4.1
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export CHART_VERSION="5.4.1"
export NAMESPACE="gitlab"
export RELEASE_NAME="gitlab"
export DOMAIN="eksdemo.tk"
export ISSUER_EMAIL="thkim@mz.co.kr"
export LOAD_BALANCE_TYPE="clb" # [clb|nlb|alb], default: clb
export GITLAB_RUNNER_INSTALL="true"
export INTERNAL='false' # [true|false]
export GITLAB_EDITION="ce" # [ce|ee]
export OMNIAUTH_ENABLED="false"
export OMNIAUTH_LABEL="Google OAuth2"
export OMNIAUTH_PROVIDERS_SECRET="gitlab-google-oauth2"
export OMNIAUTH_ID="<Your app id>"
export OMNIAUTH_SECRET="<Your app secret>"

source ../common/utils.sh

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

  for CM in $(kubectl get cm -n ${NAMESPACE} | awk -F ' ' '{print $1}');
    do kubectl delete --ignore-not-found cm/${CM} -n ${NAMESPACE}
  done

  for SECRET in $(kubectl get secret -n ${NAMESPACE} | grep ${RELEASE_NAME} | awk -F ' ' '{print $1}');
    do kubectl delete --ignore-not-found secret/${SECRET} -n ${NAMESPACE}
  done

  for PVC in $(kubectl get pvc -n ${NAMESPACE} | awk -F ' ' '{print $1}');
    do kubectl delete --ignore-not-found pvc/${PVC} -n ${NAMESPACE}
  done

  kubectl delete ns ${NAMESPACE}

  kubectl delete --ignore-not-found customresourcedefinitions\
    certificaterequests.certmanager.io\
    certificates.certmanager.io\
    challenges.certmanager.io\
    clusterissuers.certmanager.io\
    issuers.certmanager.io\
    orders.certmanager.io
  exit 0
fi

ACM_DOMAIN="*.${DOMAIN}"
ACM_ARN=$(aws acm list-certificates 2> /dev/null | jq -r -c --arg domain ${ACM_DOMAIN} '.CertificateSummaryList[] | select(.DomainName == $domain) | .CertificateArn')
if [ -z "$ACM_ARN" ]; then
  echo 'ACM is not set'
  exit 0
fi

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR
if [[ "nlb" == $LOAD_BALANCE_TYPE ]]; then
  cp ./templates/nlb.values.yaml /tmp/${DIR}/gitlab.values.yaml
elif [[ "alb" == $LOAD_BALANCE_TYPE ]]; then
  cp ./templates/alb.values.yaml /tmp/${DIR}/gitlab.values.yaml
else
  cp ./templates/clb.values.yaml /tmp/${DIR}/gitlab.values.yaml
fi
cp ./templates/google_oauth2_provider.yaml /tmp/${DIR}/provider.yaml


LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# Install Gitlab with Helm chart
##############################################################
## Add the gitlab Helm repository
if [ -z "$(helm repo list | grep https://charts.gitlab.io)" ]; then
  helm repo add gitlab https://charts.gitlab.io
fi
helm repo update

LOAD_BALANCE_INTERNAL=$INTERNAL

if [[ 'false' == $INTERNAL ]]; then
  if [[ 'clb' != $LOAD_BALANCE_TYPE ]]; then
    LOAD_BALANCE_INTERNAL="internet-facing"
  fi
else
  if [[ 'clb' != $LOAD_BALANCE_TYPE ]]; then
    LOAD_BALANCE_INTERNAL="internal"
  fi
fi

kubectl create ns ${NAMESPACE}

if [[ 'clb' != $LOAD_BALANCE_TYPE ]]; then
  OMNIAUTH_ENABLED="false"
fi

if [[ 'true' == $OMNIAUTH_ENABLED ]]; then

  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i.bak "s|OMNIAUTH_LABEL|${OMNIAUTH_LABEL}|g" /tmp/${DIR}/provider.yaml
    sed -i '' "s|OMNIAUTH_ID|${OMNIAUTH_ID}|g" /tmp/${DIR}/provider.yaml
    sed -i '' "s|OMNIAUTH_SECRET|${OMNIAUTH_SECRET}|g" /tmp/${DIR}/provider.yaml
  else
    sed -i.bak "s/OMNIAUTH_LABEL/${OMNIAUTH_LABEL}/g" /tmp/${DIR}/provider.yaml
    sed -i "s/OMNIAUTH_ID/${OMNIAUTH_ID}/g" /tmp/${DIR}/provider.yaml
    sed -i "s/OMNIAUTH_SECRET/${OMNIAUTH_SECRET}/g" /tmp/${DIR}/provider.yaml
  fi

  kubectl create secret generic ${OMNIAUTH_PROVIDERS_SECRET} \
    --from-file=provider=/tmp/${DIR}/provider.yaml \
    -n ${NAMESPACE}
fi

# kubectl create secret generic ${SMTP_PASSWORD_NAME} --from-literal=password=${AWS_SES_SECRET}

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|GITLAB_EDITION|${GITLAB_EDITION}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|DOMAIN|${DOMAIN}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|LOAD_BALANCE_INTERNAL|${LOAD_BALANCE_INTERNAL}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|ACM_ARN|${ACM_ARN}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|GITLAB_RUNNER_INSTALL|${GITLAB_RUNNER_INSTALL}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|OMNIAUTH_ENABLED|${OMNIAUTH_ENABLED}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|OMNIAUTH_PROVIDERS_SECRET|${OMNIAUTH_PROVIDERS_SECRET}|g" /tmp/${DIR}/gitlab.values.yaml
  sed -i '' "s|ISSUER_EMAIL|${ISSUER_EMAIL}|g" /tmp/${DIR}/gitlab.values.yaml
else
  ACM_ARN=$(echo ${ACM_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s/GITLAB_EDITION/${GITLAB_EDITION}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/DOMAIN/${DOMAIN}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/LOAD_BALANCE_INTERNAL/${LOAD_BALANCE_INTERNAL}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/ACM_ARN/${ACM_ARN}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/GITLAB_RUNNER_INSTALL/${GITLAB_RUNNER_INSTALL}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/OMNIAUTH_ENABLED/${OMNIAUTH_ENABLED}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/OMNIAUTH_PROVIDERS_SECRET/${OMNIAUTH_PROVIDERS_SECRET}/g" /tmp/${DIR}/gitlab.values.yaml
  sed -i "s/ISSUER_EMAIL/${ISSUER_EMAIL}/g" /tmp/${DIR}/gitlab.values.yaml
fi

helm upgrade --install ${RELEASE_NAME} gitlab/gitlab \
  --timeout 600s \
  --version=${CHART_VERSION} \
  -n ${NAMESPACE} \
  -f /tmp/${DIR}/gitlab.values.yaml \
  --wait
  # --set global.smtp.enabled=true \
  # --set global.smtp.address="email-smtp.${REGION}.amazonaws.com" \
  # --set global.smtp.port=587 \
  # --set global.smtp.user_name=${AWS_SES_KEY} \
  # --set global.smtp.password.secret=${SMTP_PASSWORD_NAME} \
  # --set global.smtp.authentication="login" \
  # --set global.smtp.starttls_auto=true \
