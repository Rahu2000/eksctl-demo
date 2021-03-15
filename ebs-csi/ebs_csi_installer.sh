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
#   chart: aws-ebs-csi 0.9.8 (0.9.0)
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_EBS_CSI_Driver_Policy"
export CONTROLLER_IAM_ROLE_NAME="AmazonEKS_EBS_CSI_Driver_Role_For_Controller"
export CONTROLLER_SERVICE_ACCOUNT="ebs-csi-controller"
export SNAPSHOT_IAM_ROLE_NAME="AmazonEKS_EBS_CSI_Driver_Role_For_Snapshot"
export SNAPSHOT_SERVICE_ACCOUNT="ebs-csi-snapshot"
export NAMESPACE="kube-system"
export CHART_VERSION="0.9.8"
export REGION="ap-northeast-2"

source ../common/utils.sh

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## download a latest policy for EBS CSI controller from kubernetes-sigs
curl -sSL -o ebs-csi-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://ebs-csi-policy.json | jq -r .Policy.Arn)
fi

CONTROLLER_IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$CONTROLLER_SERVICE_ACCOUNT" "$CONTROLLER_IAM_ROLE_NAME" "$IAM_POLICY_ARN")

SNAPSHOT_IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SNAPSHOT_SERVICE_ACCOUNT" "$SNAPSHOT_IAM_ROLE_NAME" "$IAM_POLICY_ARN")

##############################################################
# Install AWS EBS CSI DRIVER with Helm
##############################################################
LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://kubernetes-sigs.github.io/aws-ebs-csi-driver)" ]; then
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|REGION|${REGION}|g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s|CONTROLLER_SERVICE_ACCOUNT|${CONTROLLER_SERVICE_ACCOUNT}|g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s|CONTROLLER_IAM_ROLE_ARN|${CONTROLLER_IAM_ROLE_ARN}|g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s|SNAPSHOT_SERVICE_ACCOUNT|${SNAPSHOT_SERVICE_ACCOUNT}|g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s|SNAPSHOT_IAM_ROLE_ARN|${SNAPSHOT_IAM_ROLE_ARN}|g" ./templates/ebs-csi-driver.values.yaml
else
  sed -i.bak "s/REGION/${REGION}/g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s/CONTROLLER_SERVICE_ACCOUNT/${CONTROLLER_SERVICE_ACCOUNT}/g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s/CONTROLLER_IAM_ROLE_ARN|${CONTROLLER_IAM_ROLE_ARN}/g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s/SNAPSHOT_SERVICE_ACCOUNT/${SNAPSHOT_SERVICE_ACCOUNT}/g" ./templates/ebs-csi-driver.values.yaml
  sed -i '' "s/SNAPSHOT_IAM_ROLE_ARN/${SNAPSHOT_IAM_ROLE_ARN}/g" ./templates/ebs-csi-driver.values.yaml
fi

helm upgrade --install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f ./templates/ebs-csi-driver.values.yaml \
  --wait

##############################################################
# Create Storage Class
##############################################################
## Remove in-tree gp2 driver and recreate
if [[ "kubernetes.io/aws-ebs" == "$(kubectl get sc gp2 | grep gp2 | awk -F ' ' '{ print $2 }')" ]]; then
  kubectl delete sc gp2
  kubectl apply -f ./templates/gp2-storage-class.yaml
fi

## Add gp3 and io2 type StorageClass
kubectl apply -f ./templates/added-storage-class.yaml

##############################################################
## Create a PodDisruptionBudget
##############################################################
kubectl apply -f ./templates/ebs-csi-controller-pdb.yaml
kubectl apply -f ./templates/ebs-snapshot-controller-pdb.yaml