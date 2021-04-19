##############################################################
# CLUSTER UPDATE
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   chart: bitnami/metrics-server 5.7.1 (0.4.2)
##############################################################
#!/bin/bash

export METRICS_VERSION="5.7.1"
export NAMESPACE="kube-system"
export SUM_PODS_AND_SERVICES=6000

# MB required (w/ autopath) = (Pods + Services) / 250 + 56
calculate_memory () {
  d=$((($1/$2)+$3))
  echo $d
}

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"

## Patch deployments/coredns
## Notice: should be replace tolerations values
kubectl get deployments/coredns -n ${NAMESPACE} -ojson | jq '.spec.template.spec.tolerations +=  [{"key":"dedicated","operator":"Equal","value":"management","effect":"NoSchedule"}]' | jq '.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions +=  [{"key":"role","operator":"In","values":["management"]}]' | kubectl apply -f -

kubectl rollout restart deployments/coredns -n ${NAMESPACE}

## Add coredns PodDisruptionBudget
kubectl apply -f ./templates/coredns-pdb.yaml

## Add the bitnami Helm repository
if [ -z "$(helm repo list | grep https://charts.bitnami.com/bitnami)" ]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

METRICS_SERVER_MEMORY=$(calculate_memory $SUM_PODS_AND_SERVICES 250 56)

## Modifying variables
if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|MEMORY|${METRICS_SERVER_MEMORY}|g" ./templates/metrics-server.values.yaml
else
  sed -i.bak "s/MEMORY/${METRICS_SERVER_MEMORY}/g" ./templates/metrics-server.values.yaml
fi

## Install the metric-server helm chart
helm upgrade --install \
  metrics-server bitnami/metrics-server \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/metrics-server.values.yaml \
  --wait

# ## TODO
# ## Add coredns hpa

## Apply priority class
kubectl apply -f ./templates/operator.priority.class.yaml