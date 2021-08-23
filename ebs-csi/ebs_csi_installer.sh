##############################################################
# AWS EBS CSI DRIVER INSTALLER
#
# Required tools
# - helm v3+
# - jq 1.6+
# - kubectl 1.16+
#
# Tested version
# - EKS v1.19
#   chart: aws-ebs-csi 0.9.8 (0.9.0)
# - EKS v1.21
#   chart: aws-ebs-csi 1.2.4 (1.1.1)
# - EKS v1.21
#   chart: aws-ebs-csi 2.1.0 (1.2.0)
##############################################################
#!/bin/bash
export CLUSTER_NAME="eksworkshop"
export IAM_POLICY_NAME="AmazonEKS_EBS_CSI_Driver_Policy"
export CONTROLLER_IAM_ROLE_NAME="AmazonEKS_EBS_CSI_Driver_Role_For_Controller"
export CONTROLLER_SERVICE_ACCOUNT="ebs-csi-controller"
export SNAPSHOT_ENABLE="true" # [true|false]
export SNAPSHOT_IAM_ROLE_NAME="AmazonEKS_EBS_CSI_Driver_Role_For_Snapshot"
export SNAPSHOT_SERVICE_ACCOUNT="ebs-csi-snapshot"
export NAMESPACE="kube-system"
export CHART_VERSION="2.1.0"
export REGION="ap-northeast-2"
export RELEASE_NAME="aws-ebs-csi-driver"

source ../common/utils.sh

VERSION=$(echo $CHART_VERSION | awk -F '.' '{print $1}')
##############################################################
# Delete release
##############################################################
if [ "delete" == "$1" ]; then
  kubectl delete --ignore-not-found pdb/ebs-csi-controller-pdb --namespace ${NAMESPACE}
  kubectl delete --ignore-not-found pdb/ebs-snapshot-controller-pdb --namespace ${NAMESPACE}

  helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

  kubectl delete --ignore-not-found customresourcedefinitions\
    volumesnapshotclasses.snapshot.storage.k8s.io\
    volumesnapshotcontents.snapshot.storage.k8s.io\
    volumesnapshots.snapshot.storage.k8s.io
  exit 0
fi

DIR=(`date "+%Y-%m-%d-%H%M%S"`)
mkdir -p /tmp/$DIR
cp ./templates/*.yaml /tmp/${DIR}/
cp -r ./kustomize /tmp/${DIR}/
mv /tmp/${DIR}/ebs-csi-driver.v${VERSION}.values.yaml /tmp/${DIR}/ebs-csi-driver.values.yaml

##############################################################
# Create IAM Role and ServiceAccount
##############################################################
## download a latest policy for EBS CSI controller from kubernetes-sigs
curl -sSL -o /tmp/${DIR}/ebs-csi-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json

## create a policy
IAM_POLICY_ARN=$(aws iam list-policies --scope Local 2> /dev/null | jq -c --arg policyname $IAM_POLICY_NAME '.Policies[] | select(.PolicyName == $policyname)' | jq -r '.Arn')
if [ -z "$IAM_POLICY_ARN" ]; then
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file:///tmp/${DIR}/ebs-csi-policy.json | jq -r .Policy.Arn)
fi

CONTROLLER_IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$CONTROLLER_SERVICE_ACCOUNT" "$CONTROLLER_IAM_ROLE_NAME" "$IAM_POLICY_ARN")

if [[ "true" == $SNAPSHOT_ENABLE ]]; then
  SNAPSHOT_IAM_ROLE_ARN=$(createRole "$CLUSTER_NAME" "$NAMESPACE" "$SNAPSHOT_SERVICE_ACCOUNT" "$SNAPSHOT_IAM_ROLE_NAME" "$IAM_POLICY_ARN")
else
  SNAPSHOT_ENABLE="false"
fi

##############################################################
# Install EXTERNAL SNAPSHOT CSI CRD
##############################################################
if [[ "true" == $SNAPSHOT_ENABLE ]]; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml

  kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml

  kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
fi

LOCAL_OS_KERNEL="$(uname -a | awk -F ' ' ' {print $1} ')"
##############################################################
# Install External Snapshot with aws-ebs-csi-driver:v2
##############################################################
if [[ "2" == $VERSION ]] && [[ "true" == $SNAPSHOT_ENABLE ]]; then
  curl -so /tmp/${DIR}/kustomize/rbac-snapshot-controller.yaml https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml

  curl -so /tmp/${DIR}/kustomize/snapshot-controller.yaml https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i.bak "s|SNAPSHOT_IAM_ROLE_ARN|${SNAPSHOT_IAM_ROLE_ARN}|g" /tmp/${DIR}/kustomize/snapshot-serviceaccount.yaml
  else
    SNAPSHOT_IAM_ROLE_ARN=$(echo ${SNAPSHOT_IAM_ROLE_ARN} | sed 's|\/|\\/|')
    sed -i.bak "s/SNAPSHOT_IAM_ROLE_ARN/${SNAPSHOT_IAM_ROLE_ARN}/g" /tmp/${DIR}/kustomize/snapshot-serviceaccount.yaml
  fi

  kubectl apply -k /tmp/${DIR}/kustomize/

  echo ""
  echo "The Delete command for the snapshot controller is:"
  echo ""
  echo "kubectl delete -k /tmp/${DIR}/kustomize/"
  echo ""
  echo "you need a backup /tmp/${DIR}/kustomize/"
  echo ""
fi

##############################################################
# Install AWS EBS CSI DRIVER with Helm chart
##############################################################
## Add the aws-ebs-csi-driver Helm repository
if [ -z "$(helm repo list | grep https://kubernetes-sigs.github.io/aws-ebs-csi-driver)" ]; then
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
fi
helm repo update

if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
  sed -i.bak "s|REGION|${REGION}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  sed -i '' "s|CONTROLLER_SERVICE_ACCOUNT|${CONTROLLER_SERVICE_ACCOUNT}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  sed -i '' "s|CONTROLLER_IAM_ROLE_ARN|${CONTROLLER_IAM_ROLE_ARN}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
else
  CONTROLLER_IAM_ROLE_ARN=$(echo ${CONTROLLER_IAM_ROLE_ARN} | sed 's|\/|\\/|')
  sed -i.bak "s/REGION/${REGION}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  sed -i "s/CONTROLLER_SERVICE_ACCOUNT/${CONTROLLER_SERVICE_ACCOUNT}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  sed -i "s/CONTROLLER_IAM_ROLE_ARN/${CONTROLLER_IAM_ROLE_ARN}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
fi

if [[ "1" == $VERSION ]] && [[ "true" == $SNAPSHOT_ENABLE ]]; then
  if [ "Darwin" == "$LOCAL_OS_KERNEL" ]; then
    sed -i '' "s|SNAPSHOT_ENABLE|${SNAPSHOT_ENABLE}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
    sed -i '' "s|SNAPSHOT_SERVICE_ACCOUNT|${SNAPSHOT_SERVICE_ACCOUNT}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
    sed -i '' "s|SNAPSHOT_IAM_ROLE_ARN|${SNAPSHOT_IAM_ROLE_ARN}|g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  else
    sed -i "s/SNAPSHOT_ENABLE/${SNAPSHOT_ENABLE}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
    SNAPSHOT_IAM_ROLE_ARN=$(echo ${SNAPSHOT_IAM_ROLE_ARN} | sed 's|\/|\\/|')
    sed -i "s/SNAPSHOT_SERVICE_ACCOUNT/${SNAPSHOT_SERVICE_ACCOUNT}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
    sed -i "s/SNAPSHOT_IAM_ROLE_ARN/${SNAPSHOT_IAM_ROLE_ARN}/g" /tmp/${DIR}/ebs-csi-driver.values.yaml
  fi
fi

helm upgrade --install ${RELEASE_NAME} \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --version=${CHART_VERSION} \
  --namespace ${NAMESPACE} \
  -f /tmp/${DIR}/ebs-csi-driver.values.yaml \
  --wait

##############################################################
# Create Storage Classes
##############################################################
## Remove in-tree gp2 driver and recreate
if [[ "kubernetes.io/aws-ebs" == "$(kubectl get sc gp2 | grep gp2 | awk -F ' ' '{ print $3 }')" ]]; then
  kubectl delete sc gp2
  kubectl apply -f /tmp/${DIR}/gp2-storage-class.yaml
fi

## Add gp3 and io2 type StorageClass
kubectl apply -f /tmp/${DIR}/added-storage-class.yaml

##############################################################
## Create a PodDisruptionBudget
##############################################################
kubectl apply -f /tmp/${DIR}/ebs-csi-controller-pdb.yaml
if [[ "1" == $VERSION ]] && [[ "true" == $SNAPSHOT_ENABLE ]]; then
  kubectl apply -f /tmp/${DIR}/ebs-snapshot-controller-pdb.yaml
fi