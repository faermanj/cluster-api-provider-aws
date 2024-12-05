#!/bin/bash

# Set default cluster name if not provided
CLUSTER_NAME="${CLUSTER_NAME:-capi-quickstart}"
RESOURCE_SUFFIX="-bastion"

# AWS CLI commands to create resources
ROLE_NAME="SSMAccessRole-$CLUSTER_NAME$RESOURCE_SUFFIX"
SECURITY_GROUP_NAME="SSHAccessGroup-$CLUSTER_NAME$RESOURCE_SUFFIX"

# Check if an argument is passed, if not, use CLUSTER_NAME, then default to 'capi-quickstart'
INSTANCE_NAME="${1:-$CLUSTER_NAME}"

# Find instance ID for the instance with a name starting with the provided name
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME*" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

# If no instance is found with the first option, try using CLUSTER_NAME
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$CLUSTER_NAME*" \
    --query "Reservations[0].Instances[0].InstanceId" --output text)
fi

# If still no instance is found, fallback to the default 'capi-quickstart'
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=capi-quickstart*" \
    --query "Reservations[0].Instances[0].InstanceId" --output text)
fi

# Check if an instance ID was found
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  echo "No instance found with a name matching '$INSTANCE_NAME', '$CLUSTER_NAME', or 'capi-quickstart'."
  exit 1
fi

# Retrieve instance details
INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0]" --output json)
VPC_ID=$(echo "$INSTANCE_DETAILS" | jq -r '.VpcId')
INSTANCE_AZ=$(echo "$INSTANCE_DETAILS" | jq -r '.Placement.AvailabilityZone')
KEY_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.KeyName')
ORIGINAL_INSTANCE_PRIVATE_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.PrivateIpAddress')
ORIGINAL_SECURITY_GROUPS=$(echo "$INSTANCE_DETAILS" | jq -r '.SecurityGroups[].GroupId')

# Check if necessary details were retrieved
if [[ -z "$VPC_ID" || -z "$INSTANCE_AZ" || -z "$KEY_NAME" || -z "$ORIGINAL_INSTANCE_PRIVATE_IP" ]]; then
  echo "Failed to retrieve instance details. Please check the instance ID and AWS configuration."
  exit 1
fi

# Define the key file location
KEY_FILE="./${KEY_NAME}.pem"

# Set the instance type to t3.small
INSTANCE_TYPE="t3.small"

# Get latest Amazon Linux 2 AMI ID
AMI_ID=$(aws ssm get-parameters-by-path --path "/aws/service/ami-amazon-linux-latest" --query "Parameters[?ends_with(Name, 'amzn2-ami-hvm-x86_64-gp2')].Value" --output text)

if [ -z "$AMI_ID" ]; then
  echo "Failed to retrieve the latest Amazon Linux 2 AMI ID."
  exit 1
fi

# Check if the IAM role already exists
EXISTING_ROLE=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.RoleName" --output text 2>/dev/null)

if [ -z "$EXISTING_ROLE" ] || [ "$EXISTING_ROLE" != "$ROLE_NAME" ]; then
  # Create an IAM role with SSM access
  echo "Creating IAM role: $ROLE_NAME"
  ASSUME_ROLE_POLICY=$(cat <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
  )
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$ASSUME_ROLE_POLICY"
else
  echo "IAM role $ROLE_NAME already exists. Using the existing role."
fi

# Attach SSM managed policy to the role
echo "Attaching AmazonSSMManagedInstanceCore policy to $ROLE_NAME"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Check if the security group already exists
EXISTING_SECURITY_GROUP=$(aws ec2 describe-security-groups --group-name "$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupName" --output text 2>/dev/null)

if [ -z "$EXISTING_SECURITY_GROUP" ] || [ "$EXISTING_SECURITY_GROUP" != "$SECURITY_GROUP_NAME" ]; then
  # Create a security group in the same VPC with SSH access
  echo "Creating security group: $SECURITY_GROUP_NAME in VPC $VPC_ID"
  SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "Security group for SSH access (Instance $INSTANCE_ID)" --vpc-id "$VPC_ID" --query "GroupId" --output text)
else
  echo "Security group $SECURITY_GROUP_NAME already exists. Using the existing security group."
  SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --group-name "$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text)
fi

# Add a rule to allow SSH access from all IPs
echo "Adding SSH access rule to security group: $SECURITY_GROUP_ID"
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

# Find a public subnet in the same AZ
PUBLIC_SUBNET=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$INSTANCE_AZ" "Name=tag:Name,Values=*public*" --query "Subnets[0].SubnetId" --output text)

if [ -z "$PUBLIC_SUBNET" ] || [ "$PUBLIC_SUBNET" == "None" ]; then
  echo "No public subnet found in the same AZ ($INSTANCE_AZ) for VPC ($VPC_ID)."
  exit 1
fi

# Launch a new instance with the created IAM role and security group
echo "Launching a new instance with the SSM role and SSH security group..."
NEW_INSTANCE=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$PUBLIC_SUBNET" \
  --iam-instance-profile Name="$ROLE_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --query "Instances[0].InstanceId" \
  --output text)

if [ -z "$NEW_INSTANCE" ] || [ "$NEW_INSTANCE" == "None" ]; then
  echo "Failed to launch a new instance."
  exit 1
fi

echo "New instance created: $NEW_INSTANCE"

# Wait for the instance to be in the running state
echo "Waiting for the instance to be running..."
aws ec2 wait instance-running --instance-ids "$NEW_INSTANCE"

# Get the public IP address of the new instance
NEW_INSTANCE_IP=$(aws ec2 describe-instances --instance-ids "$NEW_INSTANCE" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

if [ -z "$NEW_INSTANCE_IP" ] || [ "$NEW_INSTANCE_IP" == "None" ]; then
  echo "Failed to retrieve the public IP address of the new instance."
  exit 1
fi

# Add the new instance to the original instance's security groups
echo "Adding the new instance to the security groups of the original instance..."
for SG_ID in $ORIGINAL_SECURITY_GROUPS; do
  aws ec2 modify-instance-attribute --instance-id "$NEW_INSTANCE" --groups "$SG_ID" "$SECURITY_GROUP_ID"
  echo "Added to security group: $SG_ID"
done

# Output SSH commands
echo "SSH into the new instance with the following command:"
echo "ssh -i $KEY_FILE ec2-user@$NEW_INSTANCE_IP"

echo "To connect to the original instance (private IP) using the new instance as a bastion:"
echo "ssh -i $KEY_FILE -A ec2-user@$NEW_INSTANCE_IP 'ssh ec2-user@$ORIGINAL_INSTANCE_PRIVATE_IP'"
