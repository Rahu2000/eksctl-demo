##############################################################
# KUBE PROXY METRIC ENABLE
#
# Required tools
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
##############################################################
#!/bin/bash

## Modify MetricBindAddress
kubectl get -n kube-system cm kube-proxy-config -o yaml | sed 's|127.0.0.1:10249$|0.0.0.0:10249|' | kubectl apply -f -

## Apply
kubectl rollout restart daemonset/kube-proxy -n kube-system