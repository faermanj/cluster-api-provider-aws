#!/bin/bash
set -x

echo "Verifying versions"
go version
docker --version
kind --version
kubectl version --client
clusterctl version


echo "Verifying system"
whoami
pwd
# newgrp docker || true
docker ps

# find .

echo "Run a build"
make clusterawsadm

echo "Dev container is ready at $(date)"
