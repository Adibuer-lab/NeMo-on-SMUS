#!/bin/bash
# Creates the IAM policy needed for the nested stack deployer Lambda
# Run via: make nested-stack-policy
set -e

AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")

POLICY_NAME="NeMoNestedStackDeployerPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "Account: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Profile: $AWS_PROFILE"

# Create policy document
POLICY_DOC=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CoreServices",
      "Effect": "Allow",
      "Action": ["cloudformation:*","ec2:*","eks:*","eks-auth:*","sagemaker:*","fsx:*","elasticloadbalancing:*","aps:*","grafana:*","cloudwatch:*","logs:*","acm:*","route53:AssociateVPCWithHostedZone"],
      "Resource": "*"
    },
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::nemo-*","arn:aws:s3:::nemo-*/*","arn:aws:s3:::aws-sagemaker-*","arn:aws:s3:::aws-sagemaker-*/*"]
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": ["arn:aws:iam::${ACCOUNT_ID}:role/nemo-*","arn:aws:iam::${ACCOUNT_ID}:role/HyperPod-*","arn:aws:iam::${ACCOUNT_ID}:role/sagemaker-*","arn:aws:iam::${ACCOUNT_ID}:role/service-role/*"],
      "Condition": {"StringEquals": {"iam:PassedToService": ["eks.amazonaws.com","pods.eks.amazonaws.com","sagemaker.amazonaws.com","lambda.amazonaws.com","eks-fargate-pods.amazonaws.com","states.amazonaws.com"]}}
    },
    {
      "Sid": "IAMRoleMgmt",
      "Effect": "Allow",
      "Action": ["iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:TagRole","iam:PutRolePolicy","iam:GetRolePolicy","iam:DeleteRolePolicy","iam:AttachRolePolicy","iam:DetachRolePolicy","iam:ListRolePolicies","iam:ListAttachedRolePolicies","iam:CreatePolicy","iam:DeletePolicy","iam:GetPolicy","iam:CreatePolicyVersion","iam:DeletePolicyVersion","iam:ListPolicyVersions","iam:CreateInstanceProfile","iam:DeleteInstanceProfile","iam:AddRoleToInstanceProfile","iam:RemoveRoleFromInstanceProfile","iam:GetInstanceProfile"],
      "Resource": ["arn:aws:iam::${ACCOUNT_ID}:role/nemo-*","arn:aws:iam::${ACCOUNT_ID}:role/HyperPod-*","arn:aws:iam::${ACCOUNT_ID}:role/sagemaker-*","arn:aws:iam::${ACCOUNT_ID}:role/service-role/*","arn:aws:iam::${ACCOUNT_ID}:policy/*","arn:aws:iam::${ACCOUNT_ID}:instance-profile/*"]
    },
    {
      "Sid": "IAMOIDCProviders",
      "Effect": "Allow",
      "Action": ["iam:CreateOpenIDConnectProvider","iam:DeleteOpenIDConnectProvider","iam:GetOpenIDConnectProvider","iam:TagOpenIDConnectProvider","iam:ListOpenIDConnectProviders","iam:GetServerCertificate","iam:ListServerCertificates"],
      "Resource": "*"
    },
    {
      "Sid": "EKSServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": [
        "arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
        "arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/eks-fargate.amazonaws.com/AWSServiceRoleForAmazonEKSForFargate",
        "arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/fsx.amazonaws.com/AWSServiceRoleForAmazonFSx",
        "arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/hyperpod.sagemaker.amazonaws.com/AWSServiceRoleForSageMakerHyperPod"
      ],
      "Condition": {"StringEquals": {"iam:AWSServiceName": ["eks.amazonaws.com", "eks-fargate.amazonaws.com", "fsx.amazonaws.com", "hyperpod.sagemaker.amazonaws.com"]}}
    },
    {
      "Sid": "EKSServiceLinkedRoleCheck",
      "Effect": "Allow",
      "Action": "iam:GetRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/*AWSServiceRoleForAmazonEKSForFargate"
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": ["arn:aws:lambda:*:${ACCOUNT_ID}:function:*","arn:aws:lambda:*:${ACCOUNT_ID}:layer:*"]
    },
    {
      "Sid": "ECR",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken","ecr:BatchCheckLayerAvailability","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:DescribeRepositories","ecr:DescribeImages","ecr:ListImages"],
      "Resource": "*"
    },
    {
      "Sid": "Security",
      "Effect": "Allow",
      "Action": ["kms:CreateGrant","kms:Decrypt","kms:DescribeKey","kms:Encrypt","kms:GenerateDataKey*","kms:ReEncrypt*","wafv2:*","shield:*","secretsmanager:*"],
      "Resource": "*"
    },
    {
      "Sid": "Other",
      "Effect": "Allow",
      "Action": ["sqs:*","cognito-idp:*","sso:*","organizations:DescribeOrganization","tag:GetResources","states:*","ssm:*","sts:*"],
      "Resource": "*"
    },
    {
      "Sid": "DataZoneConnections",
      "Effect": "Allow",
      "Action": ["datazone:CreateConnection","datazone:DeleteConnection","datazone:GetConnection","datazone:ListConnections","datazone:ListDomains","datazone:GetProject"],
      "Resource": "*"
    }
  ]
}
EOF
)

# Check if policy exists
if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "Policy $POLICY_NAME exists, updating..."
    
    # Delete old non-default versions if at limit
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    for v in $VERSIONS; do
        aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$v" --profile "$AWS_PROFILE" 2>/dev/null || true
    done
    
    echo "$POLICY_DOC" | aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document file:///dev/stdin \
        --set-as-default \
        --profile "$AWS_PROFILE"
    echo "Policy updated"
else
    echo "Creating policy $POLICY_NAME..."
    echo "$POLICY_DOC" | aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///dev/stdin \
        --profile "$AWS_PROFILE"
    echo "Policy created"
fi

echo ""
echo "Policy ARN: $POLICY_ARN"
echo ""
echo "This policy is used by the NestedStackDeployRole Lambda (referenced in blueprint YAML)."
echo "The provisioning role does NOT need this policy - nested stacks are deployed by the Lambda."
echo ""
echo "Services covered:"
echo "  - CloudFormation, S3, EC2/VPC, EKS, SageMaker, IAM"
echo "  - FSx, ECR, ELB, APS (Prometheus), Grafana"
echo "  - CloudWatch, Logs, ACM, KMS, Route53"
echo "  - WAF, Shield, SQS, Cognito, SSO, Organizations"
echo "  - Secrets Manager, SSM, STS, Step Functions"
