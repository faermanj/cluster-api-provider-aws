#!/bin/bash

echo "Verifying versions"
go version
kind --version
kubectl version --client
docker --version

echo "Verifying system"
docker ps
