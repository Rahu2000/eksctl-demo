# Settings after cluster creation

## Prerequisites

- [awscli v2](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)
- [jq](https://stedolan.github.io/jq/download/)
- [helm v3](https://helm.sh/ko/docs/intro/install/)

## Usage

### Install

```shell
./cluster-update.sh
```

### Enable kube-proxy monitoring for Prometheus

```shell
./kube-proxy-metric.sh
```
