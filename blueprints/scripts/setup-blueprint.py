#!/usr/bin/env python3
"""
Setup script for NeMo Tooling Blueprint and Project Profile in SageMaker Unified Studio.
Idempotent - safe to run multiple times.
Run via: make blueprint
"""

import boto3
import os
import sys
from pathlib import Path

def get_config():
    """Get config from environment variables (exported by Makefile)."""
    required = ['AWS_REGION', 'DOMAIN_ID']
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        print(f"Error: Missing env vars: {', '.join(missing)}")
        print("Run: make env ENV=<name> first, or set in .env")
        sys.exit(1)
    
    return {
        'AWS_PROFILE': os.environ.get('AWS_PROFILE', 'default'),
        'AWS_REGION': os.environ['AWS_REGION'],
        'DOMAIN_ID': os.environ['DOMAIN_ID'],
        'PROJECT_PROFILE_NAME': os.environ.get('PROJECT_PROFILE_NAME', 'NeMo-HyperPod-Profile'),
    }

def get_clients(config):
    """Create AWS clients with profile."""
    session = boto3.Session(
        profile_name=config.get('AWS_PROFILE'),
        region_name=config.get('AWS_REGION', 'us-east-1')
    )
    return {
        'datazone': session.client('datazone'),
        's3': session.client('s3'),
        'sts': session.client('sts')
    }

def find_blueprint(client, domain_id, blueprint_name):
    """Find existing custom blueprint by name."""
    try:
        paginator = client.get_paginator('list_environment_blueprints')
        for page in paginator.paginate(domainIdentifier=domain_id, managed=False):
            for bp in page.get('items', []):
                if bp.get('name') == blueprint_name:
                    return bp
    except Exception as e:
        print(f"Warning: Could not list blueprints: {e}")
    return None

def find_project_profile(client, domain_id, profile_name):
    """Find existing project profile by name."""
    try:
        paginator = client.get_paginator('list_project_profiles')
        for page in paginator.paginate(domainIdentifier=domain_id):
            for profile in page.get('items', []):
                if profile.get('name') == profile_name:
                    return profile
    except Exception as e:
        print(f"Warning: Could not list project profiles: {e}")
    return None

def upload_nemo_tooling_template(s3_client, bucket_name, region, account_id):
    """Upload NeMo-Tooling blueprint template to S3."""
    template_path = Path(__file__).parent.parent / 'nemo-tooling-blueprint.yaml'
    if not template_path.exists():
        print(f"Error: Template not found at {template_path}")
        sys.exit(1)
    
    template_key = 'blueprints/nemo-tooling-blueprint.yaml'

    # Ensure bucket exists
    try:
        s3_client.head_bucket(Bucket=bucket_name)
    except:
        print(f"Creating bucket {bucket_name}...")
        if region == 'us-east-1':
            s3_client.create_bucket(Bucket=bucket_name)
        else:
            s3_client.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )
    
    print(f"Uploading template to s3://{bucket_name}/{template_key}...")
    s3_client.upload_file(str(template_path), bucket_name, template_key)
    
    template_url = f'https://{bucket_name}.s3.{region}.amazonaws.com/{template_key}'
    return template_url

def get_nemo_tooling_user_parameters():
    """Define user-configurable parameters for the NeMo-Tooling blueprint."""
    params = [
        {'fieldType': 'STRING', 'keyName': 'HyperPodClusterName', 'description': 'Base name for the HyperPod cluster', 'isOptional': True, 'defaultValue': 'nemo-hyperpod'},
        {'fieldType': 'STRING', 'keyName': 'NeMoContainerRepository', 'description': 'ECR repository for NeMo container', 'isOptional': True, 'defaultValue': 'nemo-framework-hyperpod'},
        {'fieldType': 'STRING', 'keyName': 'NeMoContainerTag', 'description': 'NeMo container image tag', 'isOptional': True, 'defaultValue': '25.04-eks'},
        {'fieldType': 'STRING', 'keyName': 'InstanceType1', 'description': 'Instance type for training nodes (Karpenter manages scaling)', 'isOptional': True, 'defaultValue': 'ml.p4d.24xlarge'},
        {'fieldType': 'STRING', 'keyName': 'KubernetesVersion', 'description': 'Kubernetes version for EKS cluster', 'isOptional': True, 'defaultValue': '1.33'},
        {'fieldType': 'STRING', 'keyName': 'EnableTaskGovernance', 'description': 'Enable HyperPod task governance (true/false)', 'isOptional': True, 'defaultValue': 'true'},
        {'fieldType': 'STRING', 'keyName': 'EnableFSxLustre', 'description': 'Create FSx for Lustre file system (true/false)', 'isOptional': True, 'defaultValue': 'true'},
        {'fieldType': 'STRING', 'keyName': 'FSxStorageCapacity', 'description': 'FSx storage capacity in GiB (1200, 2400, or multiples of 2400)', 'isOptional': True, 'defaultValue': '1200'},
        {'fieldType': 'STRING', 'keyName': 'FSxPerUnitStorageThroughput', 'description': 'FSx throughput per TiB (125/250/500/1000)', 'isOptional': True, 'defaultValue': '250'},
        {'fieldType': 'STRING', 'keyName': 'DevModeDisableRollback', 'description': 'Dev mode: disable nested stack rollback (true/false)', 'isOptional': True, 'defaultValue': 'true'},
    ]

    # Instance group overrides are registered but optional; leave empty to use template defaults.
    for i in range(1, 21):
        params.append({
            'fieldType': 'STRING',
            'keyName': f'InstanceGroupSettings{i}',
            'description': f'Reserved: instance group settings {i} (JSON array string). Leave empty to use defaults.',
            'isOptional': True,
            'defaultValue': ''
        })

    return params

def create_or_update_nemo_tooling_blueprint(dz_client, s3_client, domain_id, provisioning_role_arn, manage_access_role_arn, region, account_id):
    """Create or update the NeMo-Tooling environment blueprint."""
    bucket_name = f'nemo-hyperpod-templates-{account_id}-{region}'
    template_url = upload_nemo_tooling_template(s3_client, bucket_name, region, account_id)
    blueprint_name = 'NeMo-Tooling'
    
    existing = find_blueprint(dz_client, domain_id, blueprint_name)
    
    if existing:
        blueprint_id = existing['id']
        print(f"Blueprint '{blueprint_name}' exists (ID: {blueprint_id})")
        
        print("Updating blueprint...")
        dz_client.update_environment_blueprint(
            domainIdentifier=domain_id,
            identifier=blueprint_id,
            description='NeMo Tooling - SageMaker domain with FSx and HyperPod cluster for distributed AI training',
            provisioningProperties={
                'cloudFormation': {'templateUrl': template_url}
            },
            userParameters=get_nemo_tooling_user_parameters()
        )
        print(f"✓ Blueprint updated")
    else:
        print(f"Creating blueprint '{blueprint_name}'...")
        response = dz_client.create_environment_blueprint(
            domainIdentifier=domain_id,
            name=blueprint_name,
            description='NeMo Tooling - SageMaker domain with FSx and HyperPod cluster for distributed AI training',
            provisioningProperties={
                'cloudFormation': {'templateUrl': template_url}
            },
            userParameters=get_nemo_tooling_user_parameters()
        )
        blueprint_id = response['id']
        print(f"✓ Blueprint created (ID: {blueprint_id})")
    
    # Enable blueprint
    print(f"Enabling blueprint in {region}...")
    config_params = {
        'domainIdentifier': domain_id,
        'environmentBlueprintIdentifier': blueprint_id,
        'enabledRegions': [region],
        'provisioningRoleArn': provisioning_role_arn
    }
    if manage_access_role_arn:
        config_params['manageAccessRoleArn'] = manage_access_role_arn
    
    try:
        dz_client.put_environment_blueprint_configuration(**config_params)
        print(f"✓ Blueprint enabled")
    except:
        print(f"✓ Blueprint already enabled")
    
    return blueprint_id

def get_tooling_blueprint_config(dz_client, domain_id):
    """Find the managed Tooling blueprint ID and its manageAccessRoleArn."""
    tooling_id = None
    paginator = dz_client.get_paginator('list_environment_blueprints')
    for page in paginator.paginate(domainIdentifier=domain_id, managed=True):
        for bp in page.get('items', []):
            if bp.get('name') == 'Tooling':
                tooling_id = bp['id']
                break
    
    if not tooling_id:
        return None, None
    
    # Get the manageAccessRoleArn from Tooling config
    try:
        config = dz_client.get_environment_blueprint_configuration(
            domainIdentifier=domain_id,
            environmentBlueprintIdentifier=tooling_id
        )
        return tooling_id, config.get('manageAccessRoleArn')
    except:
        return tooling_id, None

def get_tooling_blueprint_id(dz_client, domain_id):
    """Find the managed Tooling blueprint ID."""
    tooling_id, _ = get_tooling_blueprint_config(dz_client, domain_id)
    return tooling_id

def authorize_blueprint_for_domain_unit(dz_client, domain_id, blueprint_id, domain_unit_id, account_id):
    """Authorize the blueprint for projects in the specified domain unit."""
    entity_id = f'{account_id}:{blueprint_id}'
    
    # Grant 1: CREATE_ENVIRONMENT_PROFILE
    try:
        dz_client.add_policy_grant(
            domainIdentifier=domain_id,
            entityType='ENVIRONMENT_BLUEPRINT_CONFIGURATION',
            entityIdentifier=entity_id,
            policyType='CREATE_ENVIRONMENT_PROFILE',
            principal={
                'project': {
                    'projectDesignation': 'CONTRIBUTOR',
                    'projectGrantFilter': {
                        'domainUnitFilter': {
                            'domainUnit': domain_unit_id,
                            'includeChildDomainUnits': True
                        }
                    }
                }
            },
            detail={
                'createEnvironmentProfile': {
                    'domainUnitId': domain_unit_id
                }
            }
        )
        print(f"✓ CREATE_ENVIRONMENT_PROFILE grant added")
    except Exception as e:
        if 'conflict' in str(e).lower():
            print(f"✓ CREATE_ENVIRONMENT_PROFILE grant already exists")
        else:
            print(f"Warning: Could not add CREATE_ENVIRONMENT_PROFILE grant: {e}")
    
    # Grant 2: CREATE_ENVIRONMENT_FROM_BLUEPRINT
    try:
        dz_client.add_policy_grant(
            domainIdentifier=domain_id,
            entityType='ENVIRONMENT_BLUEPRINT_CONFIGURATION',
            entityIdentifier=entity_id,
            policyType='CREATE_ENVIRONMENT_FROM_BLUEPRINT',
            principal={
                'project': {
                    'projectDesignation': 'CONTRIBUTOR',
                    'projectGrantFilter': {
                        'domainUnitFilter': {
                            'domainUnit': domain_unit_id,
                            'includeChildDomainUnits': True
                        }
                    }
                }
            },
            detail={
                'createEnvironmentFromBlueprint': {}
            }
        )
        print(f"✓ CREATE_ENVIRONMENT_FROM_BLUEPRINT grant added")
    except Exception as e:
        if 'conflict' in str(e).lower():
            print(f"✓ CREATE_ENVIRONMENT_FROM_BLUEPRINT grant already exists")
        else:
            print(f"Warning: Could not add CREATE_ENVIRONMENT_FROM_BLUEPRINT grant: {e}")

def create_or_update_project_profile(dz_client, domain_id, profile_name, nemo_tooling_blueprint_id, tooling_blueprint_id, region, account_id):
    """Create or update the project profile."""
    existing = find_project_profile(dz_client, domain_id, profile_name)
    
    # Tooling (order 0), NeMo-Tooling (order 1)
    tooling_config = {
        'environmentBlueprintId': tooling_blueprint_id,
        'name': 'Tooling',
        'description': 'Base tooling environment (IAM roles, security groups)',
        'deploymentMode': 'ON_CREATE',
        'deploymentOrder': 0,
        'awsAccount': {'awsAccountId': account_id},
        'awsRegion': {'regionName': region}
    }
    
    nemo_tooling_config = {
        'environmentBlueprintId': nemo_tooling_blueprint_id,
        'name': 'NeMo Tooling',
        'description': 'SageMaker domain with FSx and HyperPod cluster',
        'deploymentMode': 'ON_CREATE',
        'deploymentOrder': 1,
        'awsAccount': {'awsAccountId': account_id},
        'awsRegion': {'regionName': region}
    }
    
    environment_configs = [tooling_config, nemo_tooling_config]
    
    if existing:
        profile_id = existing['id']
        print(f"Project profile '{profile_name}' exists (ID: {profile_id})")
        
        # For updates, preserve environment config IDs
        try:
            profile_details = dz_client.get_project_profile(
                domainIdentifier=domain_id,
                identifier=profile_id
            )
            existing_configs = profile_details.get('environmentConfigurations', [])
            for ec in existing_configs:
                bp_id = ec.get('environmentBlueprintId')
                ec_id = ec.get('id')
                if bp_id == tooling_blueprint_id and ec_id:
                    tooling_config['id'] = ec_id
                elif bp_id == nemo_tooling_blueprint_id and ec_id:
                    nemo_tooling_config['id'] = ec_id
        except Exception as e:
            print(f"Warning: Could not get profile details: {e}")
        
        print("Updating project profile...")
        dz_client.update_project_profile(
            domainIdentifier=domain_id,
            identifier=profile_id,
            description='Project profile for NeMo Framework on HyperPod',
            environmentConfigurations=environment_configs
        )
        print(f"✓ Project profile updated")
        return profile_id
    else:
        print(f"Creating project profile '{profile_name}'...")
        response = dz_client.create_project_profile(
            domainIdentifier=domain_id,
            name=profile_name,
            description='Project profile for NeMo Framework on HyperPod',
            environmentConfigurations=environment_configs,
            status='ENABLED'
        )
        profile_id = response['id']
        print(f"✓ Project profile created (ID: {profile_id})")
        return profile_id

def authorize_all_users(dz_client, domain_id, profile_id):
    """Authorize all domain users to create projects from this profile."""
    print("Authorizing all users for project profile...")
    
    # Get the domain unit ID from the profile
    try:
        profile = dz_client.get_project_profile(domainIdentifier=domain_id, identifier=profile_id)
        domain_unit_id = profile.get('domainUnitId')
        if not domain_unit_id:
            print("Warning: No domain unit ID found on profile")
            return
    except Exception as e:
        print(f"Warning: Could not get profile details: {e}")
        return
    
    # Check existing grants to preserve other profile authorizations
    existing_profiles = set()
    try:
        grants = dz_client.list_policy_grants(
            domainIdentifier=domain_id,
            entityType='DOMAIN_UNIT',
            entityIdentifier=domain_unit_id,
            policyType='CREATE_PROJECT_FROM_PROJECT_PROFILE'
        )
        for g in grants.get('grantList', []):
            # Check if this is an all-users grant
            if 'user' in g.get('principal', {}) and 'allUsersGrantFilter' in g['principal']['user']:
                profiles = g.get('detail', {}).get('createProjectFromProjectProfile', {}).get('projectProfiles', [])
                existing_profiles.update(profiles)
                if profile_id in profiles:
                    print("✓ Authorization already exists")
                    return
    except Exception as e:
        print(f"Warning: Could not check existing grants: {e}")
    
    # Add our profile to existing ones
    all_profiles = list(existing_profiles | {profile_id})
    
    try:
        dz_client.add_policy_grant(
            domainIdentifier=domain_id,
            entityIdentifier=domain_unit_id,
            entityType='DOMAIN_UNIT',
            policyType='CREATE_PROJECT_FROM_PROJECT_PROFILE',
            principal={
                'user': {
                    'allUsersGrantFilter': {}
                }
            },
            detail={
                'createProjectFromProjectProfile': {
                    'includeChildDomainUnits': True,
                    'projectProfiles': all_profiles
                }
            }
        )
        print("✓ All users authorized")
    except Exception as e:
        if 'already exists' in str(e).lower() or 'conflict' in str(e).lower():
            print("✓ Authorization already exists")
        else:
            print(f"Warning: Could not add authorization: {e}")

def main():
    print("=" * 60)
    print("NeMo Tooling Blueprint Setup")
    print("=" * 60)
    
    config = get_config()
    
    domain_id = config['DOMAIN_ID']
    clients = get_clients(config)
    account_id = clients['sts'].get_caller_identity()['Account']
    
    # Derive provisioning role ARN (standard naming convention)
    provisioning_role_arn = f'arn:aws:iam::{account_id}:role/service-role/AmazonSageMakerProvisioning-{account_id}'
    region = config['AWS_REGION']
    profile_name = config['PROJECT_PROFILE_NAME']
    
    print(f"\nConfiguration:")
    print(f"  Domain ID: {domain_id}")
    print(f"  Region: {region}")
    print(f"  Account: {account_id}")
    print(f"  Profile: {profile_name}")
    print()
    
    # Step 1: Get Tooling blueprint config (needed for manageAccessRoleArn)
    print("Step 1: Finding Tooling blueprint...")
    tooling_blueprint_id, manage_access_role_arn = get_tooling_blueprint_config(clients['datazone'], domain_id)
    if not tooling_blueprint_id:
        print("Error: Tooling blueprint not found. Ensure domain is properly configured.")
        sys.exit(1)
    print(f"✓ Tooling blueprint ID: {tooling_blueprint_id}")
    if manage_access_role_arn:
        print(f"✓ ManageAccessRole: {manage_access_role_arn}")
    
    # Step 2: Create/update NeMo-Tooling blueprint
    print("\nStep 2: Setting up NeMo-Tooling blueprint...")
    nemo_tooling_blueprint_id = create_or_update_nemo_tooling_blueprint(
        clients['datazone'], clients['s3'],
        domain_id, provisioning_role_arn, manage_access_role_arn, region, account_id
    )
    
    # Step 3: Authorize NeMo-Tooling blueprint for root domain unit
    print("\nStep 3: Authorizing blueprints for domain unit...")
    # Get root domain unit ID from domain
    domain = clients['datazone'].get_domain(identifier=domain_id)
    root_domain_unit_id = domain.get('rootDomainUnitId')
    if root_domain_unit_id:
        authorize_blueprint_for_domain_unit(
            clients['datazone'], domain_id, nemo_tooling_blueprint_id, root_domain_unit_id, account_id
        )
    else:
        print("Warning: Could not find root domain unit ID")
    
    # Step 4: Create/update project profile
    print("\nStep 4: Setting up project profile...")
    profile_id = create_or_update_project_profile(
        clients['datazone'], domain_id, profile_name, nemo_tooling_blueprint_id, tooling_blueprint_id, region, account_id
    )
    
    # Step 5: Authorize all users
    print("\nStep 5: Authorizing users...")
    authorize_all_users(clients['datazone'], domain_id, profile_id)
    
    print("\n" + "=" * 60)
    print("Setup complete!")
    print("=" * 60)
    print(f"\nNeMo-Tooling Blueprint ID: {nemo_tooling_blueprint_id}")
    print(f"Project Profile ID: {profile_id}")
    print(f"\nNext steps:")
    print(f"  1. Go to SageMaker Unified Studio")
    print(f"  2. Create a new project using '{profile_name}'")
    print(f"  3. The HyperPod cluster will be provisioned automatically")

if __name__ == '__main__':
    main()
