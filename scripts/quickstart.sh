export AWS_REGION=us-east-1
# create IAM resources
clusterawsadm bootstrap iam create-cloudformation-stack

export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
echo $AWS_B64ENCODED_CREDENTIALS

# create keypair
export AWS_SSH_KEY_NAME="capi-quickstart_$AWS_REGION"
aws ec2 create-key-pair --key-name "$AWS_SSH_KEY_NAME" --query 'KeyMaterial' --output text > "$AWS_SSH_KEY_NAME.pem"
chmod 400 "$AWS_SSH_KEY_NAME.pem"
aws ec2 describe-key-pairs --key-name "$AWS_SSH_KEY_NAME"

# create cluster
kind create cluster

# init cluster
clusterctl init --infrastructure aws

# create workload cluster configuration
export AWS_REGION=us-east-1
export AWS_CONTROL_PLANE_MACHINE_TYPE=t3.large
export AWS_NODE_MACHINE_TYPE=t3.large

export KUBERNETES_VERSION=$(clusterawsadm ami list -o json | jq -r ".items[0].spec.kubernetesVersion")
clusterctl generate cluster capi-quickstart \
  --kubernetes-version $KUBERNETES_VERSION \
  --control-plane-machine-count=3 \
  --worker-machine-count=3 \
  > capi-quickstart.yaml

kubectl apply -f capi-quickstart.yaml

# wait for instance
watch clusterctl describe cluster capi-quickstart
kubectl get kubeadmcontrolplane

# 
