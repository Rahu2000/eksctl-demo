##############################################################
# Nginx ingress controller INSTALLER
#
# Required tools
# - helm v3+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.20
#   chart: https://kubernetes.github.io/ingress-nginx (3.34.0)
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export NAMESPACE="ingress-nginx"
export SERVICE_ACCOUNT="ingress-nginx-controller"
export CHART_VERSION="3.34.0"
export REGION="ap-northeast-2"
export INTERNAL=false
export RELEASE_NAME="ingress-nginx"

##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}
  kubectl delete ns ${NAMESPACE}
  exit 0
fi

##############################################################
# Install AWS FSX CSI DRIVER with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

## Add the nginx-ingress Helm repository
if [ -z "$(helm repo list | grep https://kubernetes.github.io/ingress-nginx)" ]; then
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
fi
helm repo update

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR

if "$INTERNAL"; then
  cp ./templates/ingress-nginx-internal.values.yaml /tmp/${DIR}/values.yaml
else
  cp ./templates/ingress-nginx.values.yaml /tmp/${DIR}/values.yaml
fi

helm upgrade --install ${RELEASE_NAME} \
  ingress-nginx/ingress-nginx \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  --create-namespace \
  -f /tmp/${DIR}/values.yaml \
  --wait
