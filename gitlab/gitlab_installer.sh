##############################################################
# Gitlab INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   gitlab/gitlab 4.10.2
##############################################################
#!/bin/bash

set -x

export CLUSTER_NAME="eksworkshop"
export CHART_VERSION="4.10.2"
export NAMESPACE="gitlab"
export RELEASE_NAME="gitlab"
export DOMAIN="eksdemo.tk"
export ISSUER_EMAIL="thkim@mz.co.kr"

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

  # kubectl delete --ignore-not-found customresourcedefinitions\
  #   certificaterequests.certmanager.io\
  #   certificates.certmanager.io\
  #   challenges.certmanager.io\
  #   clusterissuers.certmanager.io\
  #   issuers.certmanager.io\
  #   orders.certmanager.io
  exit 0
fi

## Add the gitlab Helm repository
if [ -z "$(helm repo list | grep https://charts.gitlab.io)" ]; then
  helm repo add gitlab https://charts.gitlab.io
fi
helm repo update

# kubectl create secret generic ${SMTP_PASSWORD_NAME} --from-literal=password=${AWS_SES_SECRET}

helm upgrade --install ${RELEASE_NAME} gitlab/gitlab \
  --timeout 600s \
  --version=${CHART_VERSION} \
  --set global.hosts.domain=${DOMAIN} \
  --set certmanager-issuer.email=${ISSUER_EMAIL} \
  --set global.edition=ce \
  --set gitlab-runner.runners.privileged=true \
  # --set global.smtp.enabled=true \
  # --set global.smtp.address="email-smtp.${REGION}.amazonaws.com" \
  # --set global.smtp.port=587 \
  # --set global.smtp.user_name=${AWS_SES_KEY} \
  # --set global.smtp.password.secret=${SMTP_PASSWORD_NAME} \
  # --set global.smtp.authentication="login" \
  # --set global.smtp.starttls_auto=true \
  --create-namespace \
  -n ${NAMESPACE}

sleep 5

GITLAB_DNS_NAME=""
for i in {1..10}
  do
    GITLAB_DNS_NAME=$(kubectl get svc -n gitlab | grep amazonaws.com | awk -F ' ' '{print $4}')
    if [ -n "$GITLAB_DNS_NAME" ]; then
      break;
    fi
    sleep 1;
done

echo $GITLAB_DNS_NAME

if [ -z $GITLAB_DNS_NAME ]; then
  echo gitlab deployment failed.
  exit 1
fi

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|DOMAIN|${DOMAIN}|g" ./templates/gitlab-route53.json
  sed -i '' "s|DNS_NAME|${GITLAB_DNS_NAME}|g" ./templates/gitlab-route53.json
else
  sed -i.bak "s/DOMAIN/${DOMAIN}/g" ./templates/gitlab-route53.json
  sed -i "s/DNS_NAME/${GITLAB_DNS_NAME}/g" ./templates/gitlab-route53.json
fi

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | jq -r --arg domain "$DOMAIN" '.HostedZones[] | select(.Name | startswith($domain)) | .Id' | awk -F '/' '{print $3}')

if [ -n $HOSTED_ZONE_ID ]; then
  aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://./templates/gitlab-route53.json
fi