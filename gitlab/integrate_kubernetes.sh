##############################################################
# Information for integrating gitlab with kubernetes
#
# Required tools
# - aws-cli v2
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
##############################################################
#!/bin/bash

CLUSTER_NAME="eksworkshop"

aws eks update-kubeconfig --name $CLUSTER_NAME &> /dev/null

echo "API:"
echo "======================"
kubectl cluster-info | grep -E 'Kubernetes master|Kubernetes control plane' | awk '/http/ {print $NF}'

echo ""

echo "CA.pem:"
echo "======================"

SECRET=$(kubectl get secret | grep default | awk -F ' ' ' {print $1} ')
kubectl get secret $SECRET -o jsonpath="{['data']['ca\.crt']}" | base64 --decode > ca.crt
openssl x509 -in ca.crt -out ca.pem

cat ca.pem

echo ""

cat << EOF > /tmp/gitlab-admin-service-account.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: gitlab-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: gitlab
    namespace: kube-system
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: gitlab-cluster-admin
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: 'system:serviceaccounts'
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
EOF

echo 'create a gitlab-admin ServiceAccount ...'
kubectl apply -f /tmp/gitlab-admin-service-account.yaml
echo "done"
echo ""

echo 'Service Account Token:'
echo "======================"
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep gitlab | awk '{print $1}') | grep '^token' | awk -F ' ' '{print $2}'
