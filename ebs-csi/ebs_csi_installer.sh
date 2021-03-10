##############################################################
# AWS EBS CSI DRIVER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
#   aws-ebs-csi 0.9.8
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_EBS_CSI_Driver_Policy"
export NAMESPACE="kube-system"
export SERVICE_ACCOUNT="ebs-csi-controller"
export CHART_VERSION="0.9.8"
export REGION="ap-northeast-2"

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# IAM Policy for aws-load-balancer-controller ServiceAccount
##############################################################
## download a latest policy for EBS CSI controller from kubernetes-sigs
curl -sSL -o ebs-csi-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://ebs-csi-policy.json | jq -r .Policy.Arn)
fi

## Add the Jetstack Helm repository
if [ -z "$(helm repo list | grep https://kubernetes-sigs.github.io/aws-ebs-csi-driver)" ]; then
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
fi
helm repo update

## Create a serviceaccount
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=${NAMESPACE} \
  --name=${SERVICE_ACCOUNT} \
  --attach-policy-arn=${IAM_POLICY_ARN} \
  --override-existing-serviceaccounts \
  --approve

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|REGION|${REGION}|g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ./templates/ebs-csi-driver.values.yaml
else
  sed -i.bak "s/REGION/${REGION}/g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s/SERVICE_ACCOUNT/${SERVICE_ACCOUNT}/g" ./templates/ebs-csi-driver.values.yaml
fi

helm upgrade --install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/ebs-csi-driver.values.yaml \
  --wait

## Remove in-tree gp2 driver and recreate
if [[ "kubernetes.io/aws-ebs" == "$(kubectl get sc gp2 | grep gp2 | awk -F ' ' '{ print $2 }')" ]]; then
  kubectl delete sc gp2
  kubectl apply -f ./templates/gp2.yaml
fi

## Add gp3 and io2 type StorageClass
kubectl apply -f ./templates/storage-class.yaml

## Add PodDisruptionBudget
kubectl apply -f ./templates/ebs_snapshot_controller_pdb.yaml