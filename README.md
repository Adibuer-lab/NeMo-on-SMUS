# NeMo on SMUS (SageMaker Unified Studio + HyperPod)

## What This Explores

Distributed LLM training, fine-tuning, and serving are complex. Teams need GPUs, shared storage, job scheduling, container management, and observability—and they need it without becoming infrastructure experts.

This repo explores whether we can provide **standardised tooling** that lets AI engineers focus on models, not infrastructure. It investigates:

- **Fast onboarding**: Deploy a blueprint → get a working cluster with storage, scheduling, and observability
- **Centralised governance**: Quotas, priorities, and topology-aware scheduling via Kueue/Task Governance
- **LLMOps at scale**: Shared FSx filesystem for eliminating I/O bottlenecks, checkpoints, cached models, and artifact handoff between training stages
- **Self-service for teams**: Engineers run training jobs without needing to understand EKS, FSx, or HyperPod internals

## What's Being Explored

The notebook (`notebooks/01_exploratory_intro.ipynb`) explores:

| Capability | What We Look at |
|------------|-------------------|
| Shared storage | FSx for Lustre visible from Studio Space and training pods |
| Container discovery | Customised NeMo images registered in SSM, pulled by jobs |
| Scheduling | Kueue queues, priorities, topology hints for multi-node placement |
| Training (LLMFT) | SFT LoRA of llama, training via HyperPod Recipes |
| Training (NeMo 2.0) | Full fine-tune of qwen with HF→NeMo checkpoint conversion |
| Inference | Model loading with adapters at each training stage |

## Components

| Component | Purpose |
|-----------|---------|
| `blueprints/` | SMUS blueprint that provisions HyperPod + FSx + Task Governance + Observability |
| `nemo-container-pipeline/` | Builds NeMo container with EFA + AWS-OFI-NCCL for multi-node training |
| `notebooks/` | Validation and training workflows |
| `sagemaker-hyperpod-recipes/` | Training recipes and launcher (submodule) |
| `sagemaker-hyperpod-cluster-setup/` | HyperPod/EKS CloudFormation templates (submodule) |
| `sagemaker-hyperpod-training-adapter-for-nemo/` | NeMo adapter for HyperPod distributed training (submodule) |

## Quick Start

1. **Prerequisites**: SMUS domain, AWS Organizations Identity Center, AWS CLI v2, Python 3, Docker

2. **Setup**:
   ```bash
   git submodule update --init --recursive
   cp .env.template .env.<name>
   make env ENV=<name>
   make setup-all
   ```

3. **Deploy**: Create a project from the NeMo Tooling blueprint in SMUS

4. **Explore**: Open `notebooks/01_exploratory_intro.ipynb` in your deployed Space

## Key Commands

| Command | What It Does |
|---------|--------------|
| `make setup-all` | Full setup: policies, sync templates, create blueprint |
| `make blueprint` | Update blueprint and project profile |
| `make container-build` | Build and push custom NeMo container |
| `make help` | List all targets |

## Status

This is **exploratory work**—not prescriptive tooling or a reference architecture. It's exploring the art of the possible for enabling distributed LLM workloads at scale.

## Not Prescriptive

The patterns here are an approach, not *the* approach. For example:

**This repo explores**: Each SMUS project provisions its own HyperPod cluster via the blueprint.

**An alternative model**: A pre-existing HyperPod cluster (provisioned via AWS Service Catalog or shared infrastructure) where the SMUS blueprint instead creates:
- Cluster connection and onboarding notebooks
- Team namespaces and RBAC
- Scheduling policies and compute quotas (Kueue)
- FSx for Lustre folders per project
- Access to SMUS features: data pipelines, prep, analytics from enterprise data lakes, model registration, serving—all from one interface

The goal is exploring *what's possible*, not defining *what should be done*.
