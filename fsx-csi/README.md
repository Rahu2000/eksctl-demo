# Install AWS FSx CSI Driver

## Prerequisites

- [awscli v2](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)
- [jq](https://stedolan.github.io/jq/download/)
- [yq](https://github.com/mikefarah/yq)
- [helm v3](https://helm.sh/ko/docs/intro/install/)

## Usage

### Install

```shell
./fsx_csi_installer.sh
```

### Create a FSx Storage Class

```shell
./fsx_storageclass_creator.sh
```
