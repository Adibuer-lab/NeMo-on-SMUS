#!/bin/bash
# Adds IAM permissions to the SageMaker provisioning role for DataZone environment deployments
# Run via: make provisioning-policy
set -e

AWS_PROFILE="${AWS_PROFILE:-default}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")

POLICY_NAME="DataZoneProvisioningRolePolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
PROVISIONING_ROLE="AmazonSageMakerProvisioning-${ACCOUNT_ID}"

echo "Account: $ACCOUNT_ID"
echo "Profile: $AWS_PROFILE"
echo "Role: $PROVISIONING_ROLE"

POLICY_DOC=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3TemplateAccess",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::nemo-hyperpod-templates-${ACCOUNT_ID}-*",
        "arn:aws:s3:::nemo-hyperpod-templates-${ACCOUNT_ID}-*/*"
      ]
    },
    {
      "Sid": "IAMRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:UpdateAssumeRolePolicy"
      ],
      "Resource": [
        "arn:aws:iam::${ACCOUNT_ID}:role/DataZone-Env-*",
        "arn:aws:iam::${ACCOUNT_ID}:role/datazone_usr_role_*",
        "arn:aws:iam::${ACCOUNT_ID}:role/*hyperpod*",
        "arn:aws:iam::${ACCOUNT_ID}:role/*HyperPod*",
        "arn:aws:iam::${ACCOUNT_ID}:role/*nemo*"
      ]
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:InvokeFunction",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:PublishLayerVersion",
        "lambda:DeleteLayerVersion",
        "lambda:GetLayerVersion"
      ],
      "Resource": [
        "arn:aws:lambda:*:${ACCOUNT_ID}:function:*",
        "arn:aws:lambda:*:${ACCOUNT_ID}:layer:*"
      ]
    },
    {
      "Sid": "StepFunctions",
      "Effect": "Allow",
      "Action": [
        "states:CreateStateMachine",
        "states:DeleteStateMachine",
        "states:DescribeStateMachine",
        "states:UpdateStateMachine",
        "states:StartExecution",
        "states:TagResource",
        "states:UntagResource"
      ],
      "Resource": "arn:aws:states:*:${ACCOUNT_ID}:stateMachine:NeMo-*"
    },
    {
      "Sid": "SSM",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource"
      ],
      "Resource": "arn:aws:ssm:*:${ACCOUNT_ID}:parameter/sagemaker/hyperpod/*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DeleteLogGroup"
      ],
      "Resource": "arn:aws:logs:*:${ACCOUNT_ID}:log-group:/aws/*"
    },
    {
      "Sid": "EC2Describe",
      "Effect": "Allow",
      "Action": ["ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeSecurityGroups"],
      "Resource": "*"
    },
    {
      "Sid": "SageMakerUserProfiles",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateUserProfile",
        "sagemaker:DeleteUserProfile",
        "sagemaker:DescribeUserProfile",
        "sagemaker:AddTags"
      ],
      "Resource": "arn:aws:sagemaker:*:${ACCOUNT_ID}:user-profile/*/*"
    },
    {
      "Sid": "SageMakerSpaces",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateSpace",
        "sagemaker:DeleteSpace",
        "sagemaker:DescribeSpace",
        "sagemaker:UpdateSpace",
        "sagemaker:AddTags",
        "sagemaker:ListTags",
        "sagemaker:DeleteTags"
      ],
      "Resource": [
        "arn:aws:sagemaker:*:${ACCOUNT_ID}:space/*/jupyterlab-*",
        "arn:aws:sagemaker:*:${ACCOUNT_ID}:space/*/code-editor-*"
      ]
    },
    {
      "Sid": "SageMakerSpacesList",
      "Effect": "Allow",
      "Action": ["sagemaker:ListSpaces", "sagemaker:DescribeDomain", "sagemaker:ListUserProfiles"],
      "Resource": "*"
    },
    {
      "Sid": "FSxDescribe",
      "Effect": "Allow",
      "Action": "fsx:DescribeFileSystems",
      "Resource": "*"
    },
    {
      "Sid": "SageMakerStudioLifecycleConfig",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateStudioLifecycleConfig",
        "sagemaker:DeleteStudioLifecycleConfig",
        "sagemaker:DescribeStudioLifecycleConfig",
        "sagemaker:ListTags",
        "sagemaker:DeleteTags",
        "sagemaker:AddTags"
      ],
      "Resource": "arn:aws:sagemaker:*:${ACCOUNT_ID}:studio-lifecycle-config/*"
    },
    {
      "Sid": "EKSAccessEntry",
      "Effect": "Allow",
      "Action": [
        "eks:CreateAccessEntry",
        "eks:DeleteAccessEntry",
        "eks:DescribeAccessEntry",
        "eks:ListAccessEntries",
        "eks:AssociateAccessPolicy",
        "eks:DisassociateAccessPolicy",
        "eks:ListAssociatedAccessPolicies",
        "eks:TagResource"
      ],
      "Resource": [
        "arn:aws:eks:*:${ACCOUNT_ID}:cluster/nemo-hyperpod-*",
        "arn:aws:eks:*:${ACCOUNT_ID}:access-entry/nemo-hyperpod-*"
      ]
    },
    {
      "Sid": "EventBridge",
      "Effect": "Allow",
      "Action": [
        "events:PutRule",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:ListTargetsByRule",
        "events:EnableRule",
        "events:DisableRule",
        "events:TagResource",
        "events:UntagResource"
      ],
      "Resource": [
        "arn:aws:events:*:${ACCOUNT_ID}:rule/hyperpod-connection-*",
        "arn:aws:events:*:${ACCOUNT_ID}:rule/DataZone-Env-*",
        "arn:aws:events:*:${ACCOUNT_ID}:rule/fsx-userprofile-*",
        "arn:aws:events:*:${ACCOUNT_ID}:rule/nemo-user-profile-sync-*",
        "arn:aws:events:*:${ACCOUNT_ID}:rule/nemo-space-sync-*"
      ]
    },
    {
      "Sid": "SQSQueues",
      "Effect": "Allow",
      "Action": [
        "sqs:CreateQueue",
        "sqs:DeleteQueue",
        "sqs:GetQueueAttributes",
        "sqs:SetQueueAttributes",
        "sqs:TagQueue",
        "sqs:UntagQueue"
      ],
      "Resource": "arn:aws:sqs:*:${ACCOUNT_ID}:nemo-space-sync-*"
    }
  ]
}
EOF
)

# Create or update policy
if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "Policy exists, updating..."
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
else
    echo "Creating policy..."
    echo "$POLICY_DOC" | aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///dev/stdin \
        --profile "$AWS_PROFILE"
fi

# Attach to provisioning role
echo "Attaching to $PROVISIONING_ROLE..."
aws iam attach-role-policy \
    --role-name "$PROVISIONING_ROLE" \
    --policy-arn "$POLICY_ARN" \
    --profile "$AWS_PROFILE" 2>/dev/null || true

echo "✓ Done: $POLICY_ARN attached to $PROVISIONING_ROLE"
