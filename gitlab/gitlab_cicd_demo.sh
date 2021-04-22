##############################################################
# gitlab runner demo
#
# Required tools
# - git 2.31.1
# - kubectl 1.16+
#
# Tested version
#   EKS v1.19
##############################################################
#!/bin/bash

domain="eksdemo.tk"
gituser="root"
namespace="gitlab" # gitlab namespace

registry_secret_name="gitlab-registry" # project token name
registry_domain="registry.${domain}"
registry_token_user="" # project token user
registry_token_password="" # project token password
user_email="${gituser}@${domain}"

demo_project="gitlab-ci-cd-demo"
demo_source_url="https://github.com/Rahu2000/${demo_project}.git"
gitlab_project_url="https://gitlab.${domain}/${gituser}/${demo_project}.git"

password=$(kubectl get secrets gitlab-gitlab-initial-root-password -n $namespace --template={{.data.password}} | base64 -D)

# Create a imagePullsecret
echo "Create imagePullsecret {namespace: $namespace, secret_name: $registry_secret_name}"
kubectl create secret -n "$namespace" \
  docker-registry "$registry_secret_name" \
  --docker-server="$registry_domain" \
  --docker-username="$registry_token_user" \
  --docker-password="$registry_token_password" \
  --docker-email="$user_email"

echo "gitlab user $gituser passwork:"
echo "=============================="
echo $password

git clone $demo_source_url

cd $demo_project

rm -rf .git

git config user.name "$gituser"
git config user.email "$user_email"

git init
git remote add origin "$gitlab_project_url"
git add . && git commit -m "Initial commit"
git push -u origin master
