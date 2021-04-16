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
password=$(kubectl get secrets gitlab-gitlab-initial-root-password -n gitlab --template={{.data.password}} | base64 -D)

echo "gitlab user $gituser passwork:"
echo "=============================="
echo $password

git clone https://github.com/Rahu2000/gitlab-ci-cd-demo.git

cd gitlab-ci-cd-demo

rm -rf .git

git init
git remote add origin https://gitlab.eksdemo.tk/root/gitlab-ci-cd-demo.git
git add . && git commit -m "Initial commit"
git push -u origin master
