#! /bin/bash

curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs) && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt update && sudo apt install -y azure-cli make gcc

GO_LANG_VERSION=1.19
curl -L -o go.tar.gz "https://go.dev/dl/go${GO_LANG_VERSION}.linux-amd64.tar.gz" && \
    sudo tar -C /usr/local/ -xzf go.tar.gz && \
    echo "export PATH=$PATH:/usr/local/go/bin" tee ~/.zshrc ~/.bashrc

HELM_VERSION="3.9.3"
curl -L -o helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
    sudo tar -xzvf helm.tar.gz && \
    sudo mv linux-amd64/helm /usr/local/bin/

KUSTOMIZE_VERSION="4.1.3"
curl -L -o kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" && \
    sudo tar -xzvf kustomize.tar.gz && \
    sudo mv kustomize /usr/local/bin/ 

CLUSTERCTL_VERSION=1.2.1
curl -L -o clusterctl "https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERCTL_VERSION}/clusterctl-linux-amd64" && \
    chmod +x clusterctl && \
    sudo mv clusterctl /usr/local/bin/

curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash


export WORKDIR=$(pwd)
export LOCATION="eastus"
export SUFFIX=$RANDOM

export CAPI_MGMT_CLUSTER_RG_NAME="wasp-shadow-mgmt-$SUFFIX"
export CAPI_MGMT_CLUSTER_NAME="capi-mgmt-$SUFFIX"
export CAPZ_WORKER_CLUSTER_RG_NAME="wasp-shadow-work-$SUFFIX"
export CAPZ_WORKER_CLUSTER_CLUSTER_NAME="capz-work-$SUFFIX"

export SSH_KEY_PATH="$HOME/.ssh/id_rsa"

export RUNWASI_VERSION="v0.1.3"
export KUSTOMIZE_VERSION="4.1.3"
export KUBERNETES_VERSION="1.24.0"

export SPN_NAME="${CAPI_MGMT_CLUSTER_NAME}-spn"

# Generate tilt-settings.json file
DEPLOY_CONFIG=$(jq --null-input \
    --arg location "$LOCATION" \
    --arg suffix "$SUFFIX" \
    --arg capi_rg "$CAPI_MGMT_CLUSTER_RG_NAME" \
    --arg capi_cluster_name "$CAPI_MGMT_CLUSTER_NAME" \
    --arg capz_rg "$CAPZ_WORKER_CLUSTER_RG_NAME" \
    --arg capz_worker_name "$CAPZ_WORKER_CLUSTER_CLUSTER_NAME" \
    --arg spn_name "$SPN_NAME" \
    '{ "LOCATION": $location, "SUFFIX": $suffix, "CAPI_MGMT_CLUSTER_RG_NAME": $capi_rg, "CAPI_MGMT_CLUSTER_NAME": $capi_cluster_name, "CAPZ_WORKER_CLUSTER_RG_NAME": $capz_rg, "CAPZ_WORKER_CLUSTER_CLUSTER_NAME": $capz_worker_name, "SPN_NAME": $spn_name }')
echo $DEPLOY_CONFIG > config.json

az login --scope https://graph.microsoft.com//.default

if [[ ! -f "$SSH_KEY_PATH" ]]
then
    ssh-keygen -m PEM -b 4096 -t rsa -f "$SSH_KEY_PATH" -q -N "" 
fi

# Get required values for tilt-settings.json
az account show -o json > $WORKDIR/azure_account.json


## Create CAPI Management Cluster RG
az group create \
    -g $CAPI_MGMT_CLUSTER_RG_NAME \
    -l $LOCATION

export AZURE_SUBSCRIPTION_ID=$(cat $WORKDIR/azure_account.json | jq -r .id)
export AZURE_TENANT_ID=$(cat $WORKDIR/azure_account.json | jq -r .tenantId)

# Create CAPI spn
az ad sp create-for-rbac --name "${CAPI_MGMT_CLUSTER_NAME}-spn" --role contributor --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID" > $WORKDIR/azure_spn_info.json

export AZURE_CLIENT_ID=$(cat $WORKDIR/azure_spn_info.json | jq -r .appId)
export AZURE_CLIENT_SECRET=$(cat $WORKDIR/azure_spn_info.json | jq -r .password)


# Base64 encode the variables https://cluster-api.sigs.k8s.io/user/quick-start.html#initialize-the-management-cluster
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

# Settings needed for AzureClusterIdentity used by the AzureCluster
export AZURE_CLUSTER_IDENTITY_SECRET_NAME="cluster-identity-secret"
export CLUSTER_IDENTITY_NAME="cluster-identity"
export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"

# Clone required repo with CAPZ bits and change branch to wasm-flavor to deploy wasm-nodes
git clone https://github.com/devigned/cluster-api-provider-azure
cd cluster-api-provider-azure
git checkout --track origin/wasm-flavor

## Write out envs
echo '#! /bin/bash' > $WORKDIR/outputs.sh
# Base Info

echo "export AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID" >> $WORKDIR/outputs.sh 
echo "export AZURE_TENANT_ID=$export AZURE_TENANT_ID" >> $WORKDIR/outputs.sh

echo "export LOCATION=$LOCATION" >> $WORKDIR/outputs.sh
echo "export SUFFIX=$SUFFIX" >> $WORKDIR/outputs.sh

echo "export CAPI_MGMT_CLUSTER_RG_NAME=$CAPI_MGMT_CLUSTER_RG_NAME" >> $WORKDIR/outputs.sh
echo "export CAPI_MGMT_CLUSTER_NAME=$CAPI_MGMT_CLUSTER_NAME" >> $WORKDIR/outputs.sh
echo "export CAPZ_WORKER_CLUSTER_RG_NAME=$CAPZ_WORKER_CLUSTER_RG_NAME" >> $WORKDIR/outputs.sh
echo "export CAPZ_WORKER_CLUSTER_CLUSTER_NAME=$CAPZ_WORKER_CLUSTER_CLUSTER_NAME" >> $WORKDIR/outputs.sh

echo "export SSH_KEY_PATH=$SSH_KEY_PATH" >> $WORKDIR/outputs.sh

echo "export RUNWASI_VERSION=$RUNWASI_VERSION" >> $WORKDIR/outputs.sh
echo "export KUSTOMIZE_VERSION=$KUSTOMIZE_VERSION" >> $WORKDIR/outputs.sh
echo "export KUBERNETES_VERSION=$KUBERNETES_VERSION"

echo "export SPN_NAME=$SPN_NAME" >> $WORKDIR/outputs.sh
echo "export AZURE_CLIENT_ID=$AZURE_CLIENT_ID" >> $WORKDIR/outputs.sh
echo "export AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET" >> $WORKDIR/outputs.sh

echo "export AZURE_SUBSCRIPTION_ID_B64=$AZURE_SUBSCRIPTION_ID_B64" >> $WORKDIR/outputs.sh
echo "export AZURE_TENANT_ID_B64=$AZURE_TENANT_ID_B64" >> $WORKDIR/outputs.sh
echo "export AZURE_CLIENT_ID_B64=$AZURE_CLIENT_ID_B64" >> $WORKDIR/outputs.sh
echo "export AZURE_CLIENT_SECRET_B64=$AZURE_CLIENT_SECRET_B64" >> $WORKDIR/outputs.sh

echo "export AZURE_CLUSTER_IDENTITY_SECRET_NAME=$AZURE_CLUSTER_IDENTITY_SECRET_NAME" >> $WORKDIR/outputs.sh
echo "export CLUSTER_IDENTITY_NAME=$CLUSTER_IDENTITY_NAME" >> $WORKDIR/outputs.sh
echo "export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE=$AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE" >> $WORKDIR/outputs.sh

echo "export AZURE_LOCATION=$LOCATION" >> $WORKDIR/outputs.sh
echo "export AZURE_RESOURCE_GROUP=$CAPZ_WORKER_CLUSTER_RG_NAME"
# Select VM types.
echo "export AZURE_CONTROL_PLANE_MACHINE_TYPE=Standard_D2s_v3" >> $WORKDIR/outputs.sh
echo "export AZURE_NODE_MACHINE_TYPE=Standard_D2s_v3" >> $WORKDIR/outputs.sh
echo "export WORKER_MACHINE_COUNT=3" >> $WORKDIR/outputs.sh
echo "export CONTROL_PLANE_MACHINE_COUNT=3" >> $WORKDIR/outputs.sh

TILT_SETTINGS=$(jq --null-input \
    --arg subid "$AZURE_SUBSCRIPTION_ID" \
    --arg tenant "$AZURE_TENANT_ID" \
    --arg clientid "$AZURE_CLIENT_ID" \
    --arg clientsecret "$AZURE_CLIENT_SECRET" \
    '{"kustomize_substitutions": { "AZURE_SUBSCRIPTION_ID": $subid, "AZURE_TENANT_ID": $tenant, "AZURE_CLIENT_SECRET": $clientsecret, "AZURE_CLIENT_ID": $clientid } }')

echo $TILT_SETTINGS > tilt-settings.json

# bootstraping tilt
make tilt-up

# Create a secret to include the password of the Service Principal identity created in Azure
# This secret will be referenced by the AzureClusterIdentity used by the AzureCluster
kubectl create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}" --namespace "${AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE}"