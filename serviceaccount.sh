#!/bin/bash

export SERVICEACCOUNT="admin"
export NAMESPACE="admin"

CONTEXT="$(kubectl config current-context)"

kubectl create ns "${NAMESPACE}"
kubectl create sa "${SERVICEACCOUNT}" -n "${NAMESPACE}"
kubectl create clusterrolebinding "${SERVICEACCOUNT}-cluster-admin-rolebinding" \
    --clusterrole="cluster-admin" \
    --serviceaccount="${NAMESPACE}:${SERVICEACCOUNT}" \
    --namespace="${NAMESPACE}"

TOKEN=$(kubectl get secret --context "${CONTEXT}" \
    $(kubectl get serviceaccount "${SERVICEACCOUNT}" \
       --context "${CONTEXT}" \
       -n "${NAMESPACE}" \
       -o jsonpath='{.secrets[0].name}') \
    -n "${NAMESPACE}" \
    -o jsonpath='{.data.token}' | base64 --decode)

kubectl config set-credentials "${SERVICEACCOUNT}-token-user" --token "${TOKEN}"
kubectl config set-context "${CONTEXT}" --user "${SERVICEACCOUNT}-token-user"

# delete exists cluster/context/user
# kubectl config get-users # check user
# kubectl config delete-user OLD_USER
