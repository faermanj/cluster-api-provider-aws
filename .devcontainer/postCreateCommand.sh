#!/bin/bash

echo "Verifying versions"
go version
kind --version
kubectl version --client
docker --version

echo "Setup docker in docker"
curl https://raw.githubusercontent.com/faermanj/cluster-api-provider-aws/refs/heads/add-dedicated-hosts/.devcontainer/docker-in-docker-debian.sh | bash

echo "Verifying system"
whoami
newgrp docker || true
docker ps
pwd
find .

