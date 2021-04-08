# Install AWS Application Load Balancer controller

## Prerequisites

- [awscli v2](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)
- [jq](https://stedolan.github.io/jq/download/)
- [yq](https://github.com/mikefarah/yq)
- [helm v3](https://helm.sh/ko/docs/intro/install/)
- [curl](https://curl.se/download.html)
- [gnu-sed for OSX](https://formulae.brew.sh/formula/gnu-sed)
- [Prometheus](../prometheus) (Optional)

## Usage

### Install

```shell
./alb_controller_install.sh
```

### Cleanup

```shell
./alb_controller_install.sh delete
```
