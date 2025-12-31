#!/usr/bin/env python3
"""
Creates a shared IAM role for blueprint Lambdas to create DataZone connections.
The role is registered as a DataZone user profile and added as root domain owner.
Run via: make domain-role
"""

import os
import json
import boto3
from botocore.exceptions import ClientError

ROLE_NAME = "DataZoneDomainConnectionCreator"

def get_clients():
    session = boto3.Session(
        profile_name=os.getenv("AWS_PROFILE"),
        region_name=os.getenv("AWS_REGION", "us-east-1")
    )
    return session.client("iam"), session.client("datazone"), session.client("sts")

def get_account_id(sts):
    return sts.get_caller_identity()["Account"]

def create_role(iam, account_id, domain_id):
    # aws:PrincipalArn is non-spoofable - set by AWS based on caller identity
    # DataZone blueprint stacks create roles named: DataZone-Env-{envId}-ConnectionCreatorRole-{suffix}
    role_pattern = f"arn:aws:iam::{account_id}:role/DataZone-Env-*-ConnectionCreatorRole-*"
    trust_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"AWS": f"arn:aws:iam::{account_id}:root"},
                "Action": ["sts:AssumeRole", "sts:TagSession"],
                "Condition": {
                    "ArnLike": {"aws:PrincipalArn": role_pattern},
                    "StringLike": {"aws:RequestTag/datazone:projectId": "*"},
                    "StringEquals": {"aws:RequestTag/datazone:domainId": domain_id}
                }
            }
        ]
    }
    print(f"Allowed caller pattern: {role_pattern}")
    
    try:
        response = iam.create_role(
            RoleName=ROLE_NAME,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description="Shared role for blueprint Lambdas to create DataZone connections"
        )
        print(f"Created role: {ROLE_NAME}")
        return response["Role"]["Arn"]
    except ClientError as e:
        if e.response["Error"]["Code"] == "EntityAlreadyExists":
            print(f"Role {ROLE_NAME} already exists, updating trust policy...")
            iam.update_assume_role_policy(RoleName=ROLE_NAME, PolicyDocument=json.dumps(trust_policy))
            return iam.get_role(RoleName=ROLE_NAME)["Role"]["Arn"]
        raise

def attach_policy(iam, account_id, domain_id):
    policy_doc = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DomainScoped",
                "Effect": "Allow",
                "Action": ["datazone:CreateUserProfile", "datazone:GetUserProfile", "datazone:CreateProjectMembership", "datazone:DeleteProjectMembership"],
                "Resource": "*"
            },
            {
                "Sid": "IAMValidation",
                "Effect": "Allow",
                "Action": ["iam:GetRole"],
                "Resource": f"arn:aws:iam::{account_id}:role/DataZone-Env-*-ConnectionCreatorRole-*"
            },
            {
                "Sid": "ProjectScoped",
                "Effect": "Allow",
                "Action": [
                    "datazone:CreateConnection",
                    "datazone:GetConnection", 
                    "datazone:DeleteConnection",
                    "datazone:UpdateConnection"
                ],
                "Resource": "*",
                "Condition": {
                    "StringEquals": {
                        "datazone:domainId": domain_id,
                        "datazone:projectId": "${aws:PrincipalTag/datazone:projectId}"
                    }
                }
            }
        ]
    }
    iam.put_role_policy(RoleName=ROLE_NAME, PolicyName="DataZoneConnectionCreatorPolicy", PolicyDocument=json.dumps(policy_doc))
    print(f"Attached inline policy")

def create_user_profile(datazone, domain_id, role_arn):
    try:
        response = datazone.create_user_profile(domainIdentifier=domain_id, userIdentifier=role_arn, userType="IAM_ROLE")
        print(f"Created user profile: {response['id']}")
        return response["id"]
    except ClientError as e:
        if "existing" in str(e).lower() or e.response["Error"]["Code"] in ["ConflictException", "ValidationException"]:
            print(f"User profile already exists")
            return datazone.get_user_profile(domainIdentifier=domain_id, userIdentifier=role_arn, type="IAM")["id"]
        raise

def add_as_domain_owner(datazone, domain_id, root_unit_id, role_arn):
    try:
        datazone.add_entity_owner(domainIdentifier=domain_id, entityType="DOMAIN_UNIT", entityIdentifier=root_unit_id, owner={"user": {"userIdentifier": role_arn}})
        print(f"Added as root domain owner")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ValidationException" and "already exists" in str(e).lower():
            print(f"Already a domain owner")
        else:
            raise

def main():
    domain_id = os.getenv("DOMAIN_ID")
    if not domain_id:
        print("Error: DOMAIN_ID not set")
        return 1
    
    print(f"Domain: {domain_id}")
    iam, datazone, sts = get_clients()
    account_id = get_account_id(sts)
    print(f"Account: {account_id}")
    
    role_arn = create_role(iam, account_id, domain_id)
    attach_policy(iam, account_id, domain_id)
    
    root_unit_id = datazone.get_domain(identifier=domain_id)["rootDomainUnitId"]
    print(f"Root domain unit: {root_unit_id}")
    
    create_user_profile(datazone, domain_id, role_arn)
    add_as_domain_owner(datazone, domain_id, root_unit_id, role_arn)
    
    print(f"\nDone! Role ARN: {role_arn}")
    return 0

if __name__ == "__main__":
    exit(main())
