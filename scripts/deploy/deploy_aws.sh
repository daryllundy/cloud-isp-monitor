#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CDK_ROOT="$REPO_ROOT/cdk"
ENV_FILE="$REPO_ROOT/.env"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
load_env_file "$ENV_FILE"

if ! missing=$(require_env_vars AWS_REGION ALERT_EMAIL); then
    error_exit "Missing required AWS variables in .env:\n$missing"
fi

print_header "AWS ISP Monitor - Deployment Script"
echo "AWS Region: $AWS_REGION"
echo "Alert Email: $ALERT_EMAIL"
echo "Prefix: ${PREFIX:-isp-monitor}"

echo ""
echo "Checking AWS CLI authentication..."
check_aws_auth || error_exit "AWS CLI authentication failed."

cd "$CDK_ROOT"

if [ -d ".venv" ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

pip install -r requirements.txt >/dev/null

echo "Bootstrapping CDK..."
cdk bootstrap

echo "Deploying stack..."
cdk deploy --require-approval never

STACK_NAME=$(cdk list | head -n 1)
[ -n "$STACK_NAME" ] || error_exit "Could not determine deployed stack name."

OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --output json)
FUNCTION_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
FUNCTION_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="TopicArn") | .OutputValue')
ALARM_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AlarmName") | .OutputValue')

if [ -n "$FUNCTION_URL" ] && [ "$FUNCTION_URL" != "null" ]; then
    echo ""
    echo "Testing Lambda function endpoint..."
    curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"device":"test-deployment","note":"post-deployment verification"}' >/dev/null
    verify_http_endpoint "$FUNCTION_URL" "Lambda Function URL"
else
    warning_msg "Could not retrieve Function URL from stack outputs."
fi

print_header "Configuration Summary"
echo "Stack Name:   $STACK_NAME"
echo "Function:     $FUNCTION_NAME"
echo "Function URL: $FUNCTION_URL"
echo "Topic ARN:    $TOPIC_ARN"
echo "Alarm Name:   $ALARM_NAME"
