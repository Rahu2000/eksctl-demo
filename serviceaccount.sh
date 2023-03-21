#!/bin/bash

read -p "Enter Service Account name [admin]: " sa
SERVICEACCOUNT=${sa:-admin}

read -p "Enter Service Account's Namespace [admin]: " ns
NAMESPACE=${ns:-admin}

CONTEXT="$(kubectl config current-context)"

# Create namespace for service account
if [ -z "$(kubectl get ns | grep "$NAMESPACE")" ]; then
  kubectl create ns "${NAMESPACE}"
fi

# Create service account
if [ -z "$(kubectl get sa -n "${NAMESPACE}" | grep "$SERVICEACCOUNT")" ]; then
  kubectl create sa "${SERVICEACCOUNT}" -n "${NAMESPACE}"
fi

# Attach the cluster admin role to the service account
if [ -z "$(kubectl get clusterrolebinding | grep "${SERVICEACCOUNT}-cluster-admin-rolebinding")" ]; then
  kubectl create clusterrolebinding "${SERVICEACCOUNT}-cluster-admin-rolebinding" \
    --clusterrole="cluster-admin" \
    --serviceaccount="${NAMESPACE}:${SERVICEACCOUNT}"
fi

#TOKEN=$(kubectl get secret --context "${CONTEXT}" \
#    $(kubectl get serviceaccount "${SERVICEACCOUNT}" \
#       --context "${CONTEXT}" \
#       -n "${NAMESPACE}" \
#       -o jsonpath='{.secrets[0].name}') \
#    -n "${NAMESPACE}" \
#-o jsonpath='{.data.token}' | base64 --decode)

# Create long-lived API Token
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SERVICEACCOUNT}-secret
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SERVICEACCOUNT}
type: kubernetes.io/service-account-token
EOF


# Get token
TOKEN=$(kubectl get secret --context "${CONTEXT}" \
    $(kubectl get serviceaccount "${SERVICEACCOUNT}" \
       --context "${CONTEXT}" \
       -n "${NAMESPACE}" \
       -o jsonpath='{.secrets[0].name}') \
    -n "${NAMESPACE}" \
-o jsonpath='{.items[*].data.token}' | base64 --decode)

kubectl config set-credentials "${SERVICEACCOUNT}-token-user" --token "${TOKEN}"
kubectl config set-context "${CONTEXT}" --user "${SERVICEACCOUNT}-token-user"

# delete exists cluster/context/user
# kubectl config get-users # check user
# kubectl config delete-user OLD_USER
