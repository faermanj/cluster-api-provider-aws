#!/bin/bash

echo "Starting Docker"
sudo service docker start

echo "Verifying Versions"
go version
kind --version
kubectl version --client
