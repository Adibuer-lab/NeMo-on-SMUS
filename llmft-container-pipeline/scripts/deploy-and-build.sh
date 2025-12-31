#!/bin/bash
# Deploy CloudFormation stack and build NeMo container
# Run via: make llmft-container-build
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
STACK_NAME="llmft-container-pipeline"
TEMPLATE_FILE="$PIPELINE_DIR/container-pipeline.yaml"
DOCKERFILE_PATH="$PIPELINE_DIR/Dockerfile"
LOGS_DIR="$PIPELINE_DIR/logs"

# Verify source files exist
[[ ! -f "$TEMPLATE_FILE" ]] && echo "ERROR: Template not found at $TEMPLATE_FILE" && exit 1
[[ ! -f "$DOCKERFILE_PATH" ]] && echo "ERROR: Dockerfile not found at $DOCKERFILE_PATH" && exit 1

# Setup log file
mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOGS_DIR/build-${TIMESTAMP}.log"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

run_tty_cmd() {
    local cmd
    cmd="$(printf '%q ' "$@")"
    if command -v script >/dev/null 2>&1; then
        script -q -e /dev/null -c "$cmd"
    else
        "$@"
    fi
}

echo "=== NeMo Container Pipeline ==="
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Profile: ${AWS_PROFILE} | Region: $AWS_REGION"
echo ""

# Resolve caller account (used for target ECR URIs)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION" --profile "$AWS_PROFILE")
if [[ -z "$ACCOUNT_ID" ]]; then
    echo "ERROR: Unable to resolve AWS account ID"
    exit 1
fi

# Source and target base image settings
SOURCE_BASE_IMAGE="327873000638.dkr.ecr.us-east-1.amazonaws.com/hyperpod-recipes:llmft-v1.0.0-llama"
BASE_REPO_NAME="${BASE_REPO_NAME:-hyperpod-recipes-llmft-base}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-llmft-v1.0.0-llama}"
TARGET_BASE_IMAGE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_REPO_NAME}:${BASE_IMAGE_TAG}"
DOCKERFILE_FRONTEND_REPO_NAME="${DOCKERFILE_FRONTEND_REPO_NAME:-dockerfile-frontend}"
DOCKERFILE_FRONTEND_TAG="${DOCKERFILE_FRONTEND_TAG:-1-labs}"
DOCKERFILE_FRONTEND_IMAGE="${DOCKERFILE_FRONTEND_IMAGE:-${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DOCKERFILE_FRONTEND_REPO_NAME}:${DOCKERFILE_FRONTEND_TAG}}"

echo "Source base image: $SOURCE_BASE_IMAGE"
echo "Target base image: $TARGET_BASE_IMAGE"
echo "Dockerfile frontend: $DOCKERFILE_FRONTEND_IMAGE"
echo ""

# Ensure target base repo exists
if ! aws ecr describe-repositories --repository-names "$BASE_REPO_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo "Creating base ECR repository: $BASE_REPO_NAME"
    aws ecr create-repository --repository-name "$BASE_REPO_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null
fi

# Ensure dockerfile frontend repo exists when using local ECR
LOCAL_ECR_PREFIX="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/"
if [[ "$DOCKERFILE_FRONTEND_IMAGE" == "${LOCAL_ECR_PREFIX}"* ]]; then
    FRONTEND_REPO="${DOCKERFILE_FRONTEND_IMAGE#${LOCAL_ECR_PREFIX}}"
    FRONTEND_REPO="${FRONTEND_REPO%%:*}"
    if ! aws ecr describe-repositories --repository-names "$FRONTEND_REPO" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        echo "Creating dockerfile frontend ECR repository: $FRONTEND_REPO"
        aws ecr create-repository --repository-name "$FRONTEND_REPO" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null
    fi
fi

# Log in to source ECR and mirror the base image
echo "[0/4] Mirroring base image to our ECR..."
if aws ecr get-login-password --region us-east-1 --profile "$AWS_PROFILE" --registry-ids 327873000638 >/dev/null 2>&1; then
    aws ecr get-login-password --region us-east-1 --profile "$AWS_PROFILE" --registry-ids 327873000638 | docker login --username AWS --password-stdin 327873000638.dkr.ecr.us-east-1.amazonaws.com
else
    # Fallback for older CLI
    eval "$(aws ecr get-login --no-include-email --region us-east-1 --profile "$AWS_PROFILE" --registry-ids 327873000638)"
fi

aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "  Mirroring via buildx imagetools..."
if ! docker buildx imagetools create --tag "$TARGET_BASE_IMAGE" "$SOURCE_BASE_IMAGE"; then
    echo "ERROR: buildx imagetools mirror failed."
    echo "       Ensure buildx is installed and you are logged in to both source and target ECR registries."
    exit 1
fi
echo "  Mirrored base image to $TARGET_BASE_IMAGE"
echo ""

# Step 1: Inject Dockerfile into template
echo "[1/4] Preparing template..."
TEMP_TEMPLATE=$(mktemp).yaml
TEMP_DOCKERFILE=$(mktemp)
TEMP_DOCKERFILE_BUILD=$(mktemp)
sed -e "s|__LLMFT_BASE_IMAGE__|$TARGET_BASE_IMAGE|g" \
    -e "s|__DOCKERFILE_FRONTEND__|$DOCKERFILE_FRONTEND_IMAGE|g" \
    "$DOCKERFILE_PATH" > "$TEMP_DOCKERFILE_BUILD"
sed 's/^/        /' "$TEMP_DOCKERFILE_BUILD" > "$TEMP_DOCKERFILE"
sed -e "/__DOCKERFILE_CONTENT__/{
    r $TEMP_DOCKERFILE
    d
}" "$TEMPLATE_FILE" > "$TEMP_TEMPLATE"
rm -f "$TEMP_DOCKERFILE"
echo "  Injected Dockerfile into template"

# Step 2: Validate template
echo "[2/4] Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://$TEMP_TEMPLATE" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || { rm -f "$TEMP_TEMPLATE"; exit 1; }
echo "  Template valid"

# Step 3: Deploy CloudFormation
echo "[3/4] Deploying CloudFormation stack..."
aws cloudformation deploy \
    --template-file "$TEMP_TEMPLATE" \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --no-fail-on-empty-changeset

rm -f "$TEMP_TEMPLATE"

STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].StackStatus" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE")

echo "Stack Status: $STATUS"

if [[ "$STATUS" == *"FAILED"* ]] || [[ "$STATUS" == *"ROLLBACK"* ]]; then
    echo "ERROR: Stack deployment failed!"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" \
        --output table \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    exit 1
fi

# Step 3.5: Ensure build source exists in S3 (and reflects current Dockerfile)
echo "[3.5/4] Ensuring build source is present in S3..."
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SourceBucketName'].OutputValue" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE")

REPO_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Parameters[?ParameterKey=='RepositoryName'].ParameterValue" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE")

SOURCE_KEY="${REPO_NAME}/source.zip"

TMPDIR=$(mktemp -d)
ZIP_FILE="$TMPDIR/source.zip"
ZIP_FILE="$ZIP_FILE" DOCKERFILE_PATH="$TEMP_DOCKERFILE_BUILD" python3 - <<'PY'
import os
import zipfile

zip_path = os.environ["ZIP_FILE"]
dockerfile = os.environ["DOCKERFILE_PATH"]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.write(dockerfile, "Dockerfile")
PY

aws s3 cp "$ZIP_FILE" "s3://${SOURCE_BUCKET}/${SOURCE_KEY}" --region "$AWS_REGION"
rm -rf "$TMPDIR"
rm -f "$TEMP_DOCKERFILE_BUILD"
echo "  Uploaded s3://${SOURCE_BUCKET}/${SOURCE_KEY}"

# Step 4: Start CodeBuild
echo "[4/4] Starting CodeBuild..."

PROJECT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBuildProjectName'].OutputValue" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE")

BUILD_ID=$(aws codebuild start-build \
    --project-name "$PROJECT" \
    --query "build.id" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE")

echo "Build ID: $BUILD_ID"
echo "Console:  https://${AWS_REGION}.console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT}/build/${BUILD_ID}"

# Output to terminal (outside of log redirect)
exec 1>/dev/tty 2>/dev/tty
echo "Build ID: $BUILD_ID"
echo "Log file: $LOG_FILE"
exec >> "$LOG_FILE" 2>&1

# Monitor build
SEEN_LOGS=""
while true; do
    BUILD_JSON=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$AWS_REGION" 2>/dev/null)
    
    BUILD_STATUS=$(echo "$BUILD_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0]['buildStatus'])")
    CURRENT_PHASE=$(echo "$BUILD_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0].get('currentPhase','QUEUED'))")
    
    echo "[$(date '+%H:%M:%S')] $BUILD_STATUS - $CURRENT_PHASE"
    
    LOG_GROUP=$(echo "$BUILD_JSON" | python3 -c "import sys,json; b=json.load(sys.stdin)['builds'][0]; print(b.get('logs',{}).get('groupName',''))" 2>/dev/null)
    LOG_STREAM=$(echo "$BUILD_JSON" | python3 -c "import sys,json; b=json.load(sys.stdin)['builds'][0]; print(b.get('logs',{}).get('streamName',''))" 2>/dev/null)
    
    if [[ -n "$LOG_GROUP" ]] && [[ -n "$LOG_STREAM" ]]; then
        NEW_LOGS=$(aws logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$LOG_STREAM" \
            --limit 100 \
            --query "events[*].message" \
            --output text \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" 2>/dev/null || echo "")
        
        if [[ "$NEW_LOGS" != "$SEEN_LOGS" ]] && [[ -n "$NEW_LOGS" ]]; then
            echo "$NEW_LOGS"
            SEEN_LOGS="$NEW_LOGS"
        fi
    fi
    
    if [[ "$BUILD_STATUS" == "SUCCEEDED" ]]; then
        echo ""
        echo "BUILD SUCCEEDED at $(date '+%Y-%m-%d %H:%M:%S')"
        CONTAINER_URI=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query "Stacks[0].Outputs[?OutputKey=='ContainerImageUri'].OutputValue" \
            --output text \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE")
        echo "Container URI: $CONTAINER_URI"
        break
    elif [[ "$BUILD_STATUS" == "FAILED" ]] || [[ "$BUILD_STATUS" == "FAULT" ]] || [[ "$BUILD_STATUS" == "STOPPED" ]] || [[ "$BUILD_STATUS" == "TIMED_OUT" ]]; then
        echo ""
        echo "BUILD FAILED: $BUILD_STATUS at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "$BUILD_JSON" | python3 -c "
import sys,json
phases = json.load(sys.stdin)['builds'][0].get('phases',[])
for p in phases:
    status = p.get('phaseStatus','')
    ctx = p.get('contexts',[{}])
    msg = ctx[0].get('message','') if ctx else ''
    print(f\"  {p['phaseType']}: {status} {msg}\")
"
        exit 1
    fi
    
    sleep 10
done
