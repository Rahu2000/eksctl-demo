##############################################################
# SEALED SECRETS INSTALLER
#
# Required tools
# - helm v3+
# - kubectl 1.16+
#
# Tested version
#   v0.1
#     EKS v1.21
#     sealed-secrets v2.2.1 (chart: 1.16.1)
##############################################################
#!/bin/bash
export RELEASE_NAME="sealed-secrets"
export CHART_VERSION="1.16.1"
export SERVICE_ACCOUNT="sealed-secrets"
export NAMESPACE="kube-system"
export SECRET_NAME="sealed-secrets-key"
export ENABLE_INGRESS=false
export ENABLE_NETWORK_POLICY=false
export ENABLE_SERVICE_MONITOR=false
export ENABLE_GRAFANA_SIDECAR_DASHBOARD=false

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}
  kubectl get secret --namespace ${NAMESPACE} | grep ${RELEASE_NAME} | kubectl get secret $(awk -F ' ' ' {print $1} ') --namespace ${NAMESPACE} -oyaml | kubectl delete -f -
  kubectl delete crd sealedsecrets.bitnami.com
  exit 0
fi

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR
cp ./templates/*.values.yaml /tmp/${DIR}/

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# Install the sealed-secrets
##############################################################
## Add the Jetstack Helm repository
if [ -z "$(helm repo list | grep https://bitnami-labs.github.io/sealed-secrets)" ]; then
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|SECRET_NAME|${SECRET_NAME}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|ENABLE_INGRESS|${ENABLE_INGRESS}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|ENABLE_NETWORK_POLICY|${ENABLE_NETWORK_POLICY}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|ENABLE_SERVICE_MONITOR|${ENABLE_SERVICE_MONITOR}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|ENABLE_GRAFANA_SIDECAR_DASHBOARD|${ENABLE_GRAFANA_SIDECAR_DASHBOARD}|g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i '' "s|RELEASE_NAME|${RELEASE_NAME}|g" /tmp/${DIR}/sealed-secrets.values.yaml
else
  sed -i "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/SECRET_NAME/${SECRET_NAME}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/ENABLE_INGRESS/${ENABLE_INGRESS}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/ENABLE_NETWORK_POLICY/${ENABLE_NETWORK_POLICY}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/ENABLE_SERVICE_MONITOR/${ENABLE_SERVICE_MONITOR}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/ENABLE_GRAFANA_SIDECAR_DASHBOARD/${ENABLE_GRAFANA_SIDECAR_DASHBOARD}/g" /tmp/${DIR}/sealed-secrets.values.yaml
  sed -i "s/RELEASE_NAME/${RELEASE_NAME}/g" /tmp/${DIR}/sealed-secrets.values.yaml
fi

## Install the sealed-secrets helm chart
helm upgrade --install \
  ${RELEASE_NAME} sealed-secrets/sealed-secrets \
  --namespace ${NAMESPACE} \
  --version "${CHART_VERSION}" \
  -f /tmp/${DIR}/sealed-secrets.values.yaml \
  --wait

## Backup master key
kubectl get secret -n ${NAMESPACE} -l sealedsecrets.bitnami.com/${SECRET_NAME} -o yaml > ${RELEASE_NAME}-master.yaml
echo 'Backuped master key: ./'$RELEASE_NAME-master.yaml
