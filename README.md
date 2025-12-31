# NeMo on SMUS (SageMaker Unified Studio + HyperPod)

This repo explores infrastructure and tooling to learn about NVIDIA NeMo on SageMaker Unified Studio (DataZone) using SageMaker HyperPod on EKS. It includes:

- An SMUS blueprint that provisions a HyperPod cluster, FSx for Lustre, task governance/Kueue, and optional SageMaker Spaces integration.
- Infrastructure pipelines for approved NeMo/LLMFT container images.
- Notebooks that validate shared storage, container discovery, add-ons, and run recipes-based training/inference workflows.

## Entrypoints

- Blueprint template: `blueprints/nemo-tooling-blueprint.yaml`
- Capability map notebook: `notebooks/01_exploratory_intro.ipynb`

## Project Structure

- `blueprints/`: SMUS blueprint template and setup scripts.
- `domain-vpc/`: CloudFormation for VPC endpoints used by the blueprint.
- `llmft-container-pipeline/`: CodeBuild/ECR pipeline to build and publish the LLMFT custom container images.
- `sagemaker-hyperpod-cluster-setup/`: HyperPod/EKS CloudFormation templates and Lambda artifacts (submodule).
- `sagemaker-hyperpod-recipes/`: Recipes and launcher used by the notebook workflows.
- `notebooks/`: Runnable exploration and training examples.

## Prerequisites

- An existing SageMaker Unified Studio (DataZone) domain (set `DOMAIN_ID` in `.env`).
- AWS Organizations Identity Center configured (org-based Identity Center for the AWS Managed Grafana workspace that HyperPod Observability Kubernetes add-on provision).

## Local Setup

1. Initialize submodules:
   ```bash
   git submodule update --init --recursive
   ```
2. Create an env file and select it:
   ```bash
   cp .env.template .env.<name>
   make env ENV=<name>
   ```
3. Required tools:
   - AWS CLI v2
   - Python 3 + `boto3`
   - Docker (for container work)

## Common Commands

- `make help`: list available targets.
- `make artifacts`: build Lambda/container artifacts used by HyperPod templates.
- `make sync`: stage HyperPod templates/resources and sync them to `s3://nemo-hyperpod-templates-<acct>-<region>` (creates bucket + CloudFormation access policy if missing).
- `make blueprint`: upload the blueprint template to S3, create/update the NeMo Tooling SMUS blueprint, enable it, and create/update the project profile + grants.
- `make hf-secret TOKEN=...`: create/update Secrets Manager `nemo-container-build/hf-access-token` in `AWS_REGION`.
- `make provisioning-policy`: create/update `DataZoneProvisioningRolePolicy` and attach it to `AmazonSageMakerProvisioning-<acct>` (S3 templates bucket, IAM role mgmt, Lambda/StepFunctions/SSM, EventBridge + SQS for space sync, SM user profiles/spaces, EKS access entries).
- `make nested-stack-policy`: create/update `NeMoNestedStackDeployerPolicy` (CloudFormation/EC2/VPC/EKS/SageMaker/FSx/Grafana/Prometheus/IAM/ECR/etc.) used by the nested stack deployer Lambda.
- `make domain-role`: create/update the `DataZoneDomainConnectionCreator` role with a trust policy for DataZone env ConnectionCreator roles, attach its inline policy, and register it in the DataZone domain as a user profile + root owner.
- `make llmft-container-build`: deploy the LLMFT container pipeline and trigger an image build.
- `make setup-all`: run `provisioning-policy`, `nested-stack-policy`, `sync`, then `blueprint` for the current env.


## Notebook Usage (Capability Map)

The capability map notebook proves the deployed environment is working end-to-end:

- FSx for Lustre is visible in the Space and in HyperPod pods.
- Approved NeMo/LLMFT container images are discovered from SSM.
- EKS add-ons (training operator, task governance/Kueue) are present.
- Recipe-based training/inference workflows run on the cluster.

Clone the repo into your deployed Hyperpod SMUS Project and starts here: `notebooks/01_exploratory_intro.ipynb`.