#!/usr/bin/env bash
set -euo pipefail

# Follow CloudFormation events for a root stack and all nested stacks, logging output for tail -f.

export AWS_PAGER=""

usage() {
  cat <<'USAGE'
Usage: follow-cfn-stack-events.sh [options] <stack-arn-or-name>

Options:
  -p, --profile <profile>     AWS profile to use
  -r, --region <region>       AWS region (defaults to ARN region or AWS env)
  --poll <seconds>            Poll interval seconds (default: 5)
  --log-file <path>           Log file path (default: logs/cfn-events-<stack>-<timestamp>.log)
  --no-tmux                   Do not launch tmux
  --tail-lines <n>            Lines to show in tail pane (default: 200)
  -h, --help                  Show help
USAGE
}

STACK_REF=""
AWS_PROFILE_ARG=""
REGION_ARG=""
ENV_AWS_REGION="${AWS_REGION:-}"
ENV_AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-}"
POLL_INTERVAL=5
LOG_FILE=""
USE_TMUX=1
TAIL_LINES=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile)
      AWS_PROFILE_ARG="$2"
      shift 2
      ;;
    -r|--region)
      REGION_ARG="$2"
      shift 2
      ;;
    --poll)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --no-tmux)
      USE_TMUX=0
      shift
      ;;
    --tail-lines)
      TAIL_LINES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$STACK_REF" ]]; then
        STACK_REF="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac

done

if [[ -z "$STACK_REF" ]]; then
  usage >&2
  exit 1
fi

stack_name_from_ref() {
  local ref="$1"
  if [[ "$ref" == arn:aws:cloudformation:*:stack/*/* ]]; then
    local after
    after="${ref#*stack/}"
    echo "${after%%/*}"
  else
    echo "$ref"
  fi
}

region_from_ref() {
  local ref="$1"
  if [[ "$ref" == arn:aws:cloudformation:*:*:* ]]; then
    echo "${ref#arn:aws:cloudformation:}" | cut -d: -f1
  fi
}

AWS_REGION=""
if [[ -n "$REGION_ARG" ]]; then
  AWS_REGION="$REGION_ARG"
elif [[ "$STACK_REF" == arn:aws:cloudformation:*:*:* ]]; then
  AWS_REGION="$(region_from_ref "$STACK_REF")"
elif [[ -n "$ENV_AWS_REGION" ]]; then
  AWS_REGION="$ENV_AWS_REGION"
elif [[ -n "$ENV_AWS_DEFAULT_REGION" ]]; then
  AWS_REGION="$ENV_AWS_DEFAULT_REGION"
else
  AWS_REGION="us-east-1"
fi

AWS_ARGS=(--region "$AWS_REGION")
if [[ -n "$AWS_PROFILE_ARG" ]]; then
  AWS_ARGS+=(--profile "$AWS_PROFILE_ARG")
fi

aws_cli() {
  aws "${AWS_ARGS[@]}" "$@"
}

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found in PATH." >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  if command -v realpath >/dev/null 2>&1; then
    REPO_ROOT=$(realpath "$SCRIPT_DIR/..")
  else
    REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
  fi
fi
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"

STACK_NAME_SAFE=$(stack_name_from_ref "$STACK_REF" | tr -c 'a-zA-Z0-9._-' '_')
if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE="$LOG_DIR/cfn-events-${STACK_NAME_SAFE}-$(date +%Y%m%d-%H%M%S).log"
fi
touch "$LOG_FILE"

log_line() {
  local line="$1"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

# Launch tmux with watcher and tail panes unless already inside tmux or disabled.
if [[ "$USE_TMUX" -eq 1 && -z "${TMUX:-}" ]]; then
  if command -v tmux >/dev/null 2>&1; then
    SESSION_NAME="cfn-${STACK_NAME_SAFE}-$(date +%H%M%S)"
    CMD=("$0" "--no-tmux" "--poll" "$POLL_INTERVAL" "--log-file" "$LOG_FILE")
    if [[ -n "$AWS_PROFILE_ARG" ]]; then
      CMD+=("--profile" "$AWS_PROFILE_ARG")
    fi
    if [[ -n "$AWS_REGION" ]]; then
      CMD+=("--region" "$AWS_REGION")
    fi
    CMD+=("$STACK_REF")

    tmux new-session -d -s "$SESSION_NAME" "${CMD[*]}"
    tmux split-window -h "tail -n $TAIL_LINES -f \"$LOG_FILE\""
    tmux select-layout -t "$SESSION_NAME" even-horizontal
    tmux set-option -t "$SESSION_NAME" remain-on-exit on
    tmux attach -t "$SESSION_NAME"
    exit 0
  else
    echo "tmux not found; running in current shell." >&2
  fi
fi

RED=$'\033[31m'
YELLOW=$'\033[33m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

is_failure_status() {
  local status="$1"
  if [[ "$status" == *"FAILED"* || "$status" == *"ROLLBACK"* ]]; then
    return 0
  fi
  return 1
}

is_terminal_status() {
  local status="$1"
  case "$status" in
    *_COMPLETE|*_FAILED|*_ROLLBACK_COMPLETE|*_ROLLBACK_FAILED|DELETE_COMPLETE|DELETE_FAILED)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

get_stack_status() {
  local ref="$1"
  local out
  if ! out=$(aws_cli cloudformation describe-stacks --stack-name "$ref" --query 'Stacks[0].StackStatus' --output text 2>&1); then
    log_line "${YELLOW}WARN${RESET} Unable to get stack status for $ref: $out"
    return 1
  fi
  echo "$out"
}

get_nested_stack_refs() {
  local ref="$1"
  local out
  if ! out=$(aws_cli cloudformation list-stack-resources --stack-name "$ref" \
    --query "StackResourceSummaries[?ResourceType=='AWS::CloudFormation::Stack'].PhysicalResourceId" \
    --output text 2>&1); then
    log_line "${YELLOW}WARN${RESET} Unable to list resources for $ref: $out"
    return 0
  fi

  if [[ -z "$out" || "$out" == "None" ]]; then
    return 0
  fi

  # Output may be tab-separated; convert to lines
  echo "$out" | tr '\t' '\n'
}

emit_stack_events() {
  local ref="$1"
  local out
  if ! out=$(aws_cli cloudformation describe-stack-events --stack-name "$ref" \
    --query 'StackEvents[].[EventId,Timestamp,ResourceStatus,ResourceStatusReason,LogicalResourceId,ResourceType,PhysicalResourceId]' \
    --output text 2>&1); then
    log_line "${YELLOW}WARN${RESET} Unable to describe events for $ref: $out"
    return 0
  fi

  if [[ -z "$out" || "$out" == "None" ]]; then
    return 0
  fi

  mapfile -t lines <<< "$out"
  local i
  for (( i=${#lines[@]}-1; i>=0; i-- )); do
    local line="${lines[$i]}"
    [[ -z "$line" ]] && continue
    IFS=$'\t' read -r event_id ts status reason logical_id resource_type physical_id <<< "$line"
    if [[ -n "${SEEN_EVENT_IDS[$event_id]:-}" ]]; then
      continue
    fi
    SEEN_EVENT_IDS[$event_id]=1

    if [[ "$reason" == "None" || -z "$reason" ]]; then
      reason="-"
    fi

    local stack_label
    stack_label=$(stack_name_from_ref "$ref")
    local msg="[$ts] [$stack_label] [$status] $logical_id ($resource_type) - $reason"

    if [[ "$resource_type" == "AWS::CloudFormation::Stack" && -n "$physical_id" && "$physical_id" != "None" && "$physical_id" != "-" ]]; then
      if [[ -z "${KNOWN_STACKS[$physical_id]:-}" ]]; then
        KNOWN_STACKS[$physical_id]=1
        log_line "Discovered nested stack (event): $physical_id"
      fi
    fi

    if is_failure_status "$status"; then
      log_line "${RED}${BOLD}FAIL${RESET} ${RED}${msg}${RESET}"
    else
      log_line "$msg"
    fi
  done
}

log_line "Starting CloudFormation event follow for: $STACK_REF (region: $AWS_REGION)"
log_line "Log file: $LOG_FILE"

declare -A KNOWN_STACKS=()
declare -A SEEN_EVENT_IDS=()

KNOWN_STACKS["$STACK_REF"]=1

DISCOVERY_INTERVAL=15
LAST_DISCOVERY=0
ROOT_TERMINAL_SEEN=0

while true; do
  now=$(date +%s)
  if (( now - LAST_DISCOVERY >= DISCOVERY_INTERVAL )); then
    for ref in "${!KNOWN_STACKS[@]}"; do
      while IFS= read -r nested_ref; do
        [[ -z "$nested_ref" || "$nested_ref" == "None" ]] && continue
        if [[ -z "${KNOWN_STACKS[$nested_ref]:-}" ]]; then
          KNOWN_STACKS[$nested_ref]=1
          log_line "Discovered nested stack: $nested_ref"
        fi
      done < <(get_nested_stack_refs "$ref")
    done
    LAST_DISCOVERY=$now
  fi

  for ref in "${!KNOWN_STACKS[@]}"; do
    emit_stack_events "$ref"
  done

  root_status="$(get_stack_status "$STACK_REF" || echo "UNKNOWN")"
  if is_terminal_status "$root_status"; then
    if [[ "$ROOT_TERMINAL_SEEN" -eq 0 ]]; then
      ROOT_TERMINAL_SEEN=1
      log_line "${YELLOW}Root stack reached terminal status: $root_status. Final sweep...${RESET}"
      sleep "$POLL_INTERVAL"
      continue
    fi
    log_line "${YELLOW}Exiting: root stack terminal status $root_status.${RESET}"
    break
  fi

  sleep "$POLL_INTERVAL"
done
