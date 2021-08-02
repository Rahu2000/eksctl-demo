# Install Sealed Secrets

## Prerequisites

- [awscli v2](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)
- [helm v3](https://helm.sh/ko/docs/intro/install/)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets/releases)

## Usage

### Install

```shell
./sealed_secrets_installer.sh
```

### Cleanup

```shell
./sealed_secrets_installer.sh delete
```

## How to use

### Install kubeseal

#### LINUX

```shell
KUBESEAL_VERSION=v0.16.0
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-linux-amd64 -O kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Create a sealed secret file

Secret infomation
name: database-credentials
namespace: default
data:
  username=admin
  password=Tru5tN0!

```shell
cat << EOF > kustomization.yaml
namespace: default
secretGenerator:
- name: database-credentials
  literals:
  - username=admin
  - password=Tru5tN0!
generatorOptions:
  disableNameSuffixHash: true
EOF

kubectl kustomize . > secret.yaml

KUBESEAL_CONTROLLER_NAME="sealed-secrets"
KUBESEAL_CONTROLLER_NAMESPACE="kube-system"

kubeseal \
--controller-name=${KUBESEAL_CONTROLLER_NAME} \
--controller-namespace=${KUBESEAL_CONTROLLER_NAMESPACE} \
--format=yaml < secret.yaml > sealed-secret.yaml
```

### Check sealed-secret.yaml

```shell
cat sealed-secret.yaml
```

```text
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: database-credentials
  namespace: default
spec:
  encryptedData:
    password: AgCD3IXlY47FXPsNfwg4HGmAc+0DywxNcWLIvd8x5z8iaequ/r3yUOQ6Sgn8QFWgE8rhRB4TKCqd6OW83fgmnEExTERirjTk3gLao6qRdTpS0DzDJBIZsj9WlCpjj5yHQE9CHLspij4+Vh+UewgHxoFRmZkr3hX4YXzz3EgYo5qUwoW2KsgoJ3N1ZjrQexq0gMw/ujA4jhfeC4sETtIPxRqXLxZq0TB0sYrFL4YkWoUHJFCO7QkDU1Ji+cmO/MLeaO5DsVzIWcARaQlmXndLaNtT5xiMSo4573IedgKWV7B3QagRjkB2BeL/S2DnInlfVfbsSPaH1h3s2ubzrrfps0av2jb1/oeMe75qZuMZs8tSScX9fG8Ss+MqUjOzNDUBDi0m4rq4hxdGSKOOeYLjyCT3h1GehWFKowmK0pj5ZhxCkvBtTAayd0Kx9P09mE8TuJsFkmiGanKfqzAZnZfBLsvbc8XvmmJZOjjUj39t6MyXBEvC8PScJ05aqW2hTYsbjlcyPSkiu1IV2CQgJo27M7azE9RomDyc/xE4lJ2ABt0dgRGsff/pGatW901Ey1IBWv0qU1IxfoEGL48rSH0hD3RO4payh0EvVX5i5KvDG1Jw03hSTSrkHJUMtsKVrDVa7XnbXRqCUXTn5nUwTq+/P7pi5JLg8h60a2F7sPahBA7FbgR7q8EGqdruO5EH92u2MqrYT0Zdw00b2A==
    username: AgChSIvjqOTpm9FFG/sjFh7YW3rupT97tDOy3vIYXMj+arsZ9yHSuDZVFOaLWQghzj3DGeUhdYUXTyQvDKp1Rcb1jBcMP9mXIrqSyBVGYFikJELDxz09VKd9au0AqQDdz1tWc/lhvCMXmliC0AuUjuOCDP4lUp5X88fGSMBGnrpVkOnt3VIqHARwBzqcRVKlMZXk3Svkn9JlrQS6niwC+RwP5D8/kBoN4y2jMlFpCzL4J0ZTxK21gv7fKUuS9evX7TctCMgkzePmT/qLPkxAWY0ZDibLt/WVnYo+DqA2mu7iMZC0wyBrk7ruIOr73Q2AqUcNp5i+vkzIhXb8CsV+2PwRBrDD6H5xnGg1ZfNf0v3T0DmzU2mqcEjSEvR3/2BRWlbI4ao71v5b0QjvS0QKHXVakIHwNk9fB2zvkLe122Z9QRxuM2o6mYR30yMUQOuqJw3E3Bbl8EAmEj0po6uX4xO6uW37QmI+ZwFoXi9TmURFIthJQvXCPdWOLfCb1lWR59bwr3hxB8mBSvVaLghEqe3ukWao9BPFoin9UDi1ajFXxgLjCjF5vSkGVkv2q573gRrwXSkdTXEWmliNcoNeGLnUhtAp0FHYx//mbouaPDzh6Fj7j0Vzzz2Lc+HtgZ7ikme7HyjMz08ooHpdSIdVD7EWfIgkznVkqRuPsdufcMYo21oZVeI/TNHbRJ/3+RI7F7zhpV2mnA==
  template:
    data: null
    metadata:
      creationTimestamp: null
      name: database-credentials
      namespace: default
    type: Opaque
```

### Create kubernetes secret

```shell
kubectl apply -f sealed-secret.yaml
```

### Verification

```shell
kubectl get secrets database-credentials -n default

NAME                   TYPE     DATA   AGE
database-credentials   Opaque   2      5s
```