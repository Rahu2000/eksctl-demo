# eksctl-demo

## Prerequisites

- [eksctl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/eksctl.html)

## Usage

### Create cluster

```shell
eksctl create cluster -f create-cluster.yaml
```

### Delete cluster

```shell
eksctl delete cluster --name {EKS_CLUSTER_NAME} --wait
```
