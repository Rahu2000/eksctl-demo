# Install Prometheus

## Prerequisites

- [awscli v2](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)
- [jq](https://stedolan.github.io/jq/download/)
- [helm v3](https://helm.sh/ko/docs/intro/install/)
- [EBS CSI](../ebs-csi/README.md) (Kubernetes 1.18+)

## Usage

### Install

```shell
./prometheus_installer.sh
```

### Cleanup

```shell
./prometheus_installer.sh delete
```
