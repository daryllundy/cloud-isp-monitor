#!/bin/bash
set -e

# Load .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Validation
REQUIRED_VARS=("AWS_REGION" "ALERT_EMAIL")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set in .env or environment"
    echo "Please copy .env.example to .env and configure it."
    exit 1
  fi
done

# Check AWS CLI
echo "Checking AWS CLI authentication..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "Error: Not authenticated to AWS CLI info. Please run 'aws configure' or check your credentials."
    exit 1
fi

echo "Deploying to AWS Region: $AWS_REGION with Alert Email: $ALERT_EMAIL"

cd cdk

# Activate venv if it exists
if [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# Install requirements
pip install -r requirements.txt

# Bootstrap CDK (only if needed, but safe to run)
echo "Bootstrapping CDK..."
cdk bootstrap

# Deploy
echo "Deploying Stack..."
cdk deploy --require-approval never

echo "Deployment complete."
echo "---------------------------------------------------"

# Get Stack Name (assuming only one stack is returned by cdk list or taking the first one)
STACK_NAME=$(cdk list | head -n 1)
echo "Stack Name: $STACK_NAME"

# Get outputs
if [ -n "$STACK_NAME" ]; then
    echo "Retrieving stack outputs..."
    
    # Get outputs in JSON format for parsing
    OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --output json)
    
    # Display outputs in table format
    echo "$OUTPUTS" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'
    
    # Extract Function URL
    FUNCTION_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
    FUNCTION_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
    SNS_TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SnsTopicArn") | .OutputValue')
    ALARM_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AlarmName") | .OutputValue')
    
    echo ""
    echo "---------------------------------------------------"
    echo "POST-DEPLOYMENT VERIFICATION"
    echo "---------------------------------------------------"
    
    # Test Lambda function URL
    if [ -n "$FUNCTION_URL" ] && [ "$FUNCTION_URL" != "null" ]; then
        echo ""
        echo "Testing Lambda function endpoint..."
        echo "URL: $FUNCTION_URL"
        
        # Test with curl
        HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d '{"device":"test-deployment","note":"post-deployment verification"}' 2>&1)
        
        HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)
        RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ Function endpoint is responding correctly (HTTP 200)"
            echo "  Response: $RESPONSE_BODY"
        else
            echo "⚠ Function returned HTTP $HTTP_CODE. Check logs for details."
            echo "  Response: $RESPONSE_BODY"
        fi
    else
        echo "⚠ Could not retrieve Function URL from stack outputs"
    fi
    
    echo ""
    echo "---------------------------------------------------"
    echo "CONFIGURATION SUMMARY"
    echo "---------------------------------------------------"
    echo "Function Name:    $FUNCTION_NAME"
    echo "Function URL:     $FUNCTION_URL"
    echo "SNS Topic ARN:    $SNS_TOPIC_ARN"
    echo "Alarm Name:       $ALARM_NAME"
    echo "Alert Email:      $ALERT_EMAIL"
    echo "AWS Region:       $AWS_REGION"
    
    echo ""
    echo "---------------------------------------------------"
    echo "NEXT STEPS"
    echo "---------------------------------------------------"
    echo ""
    echo "1. CONFIGURE HEARTBEAT AGENT:"
    echo "   Update your .env file with:"
    echo "   HEARTBEAT_URL=\"$FUNCTION_URL\""
    echo "   HEARTBEAT_DEVICE=\"your-device-name\""
    echo "   HEARTBEAT_INTERVAL=\"60\""
    echo ""
    echo "2. START HEARTBEAT AGENT:"
    echo "   ./start_heartbeat.sh"
    echo ""
    echo "3. VERIFY CLOUDWATCH LOGS:"
    echo "   aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
    echo ""
    echo "4. TEST ALERT SYSTEM:"
    echo "   a. Stop the heartbeat agent:"
    echo "      ./stop_heartbeat.sh"
    echo ""
    echo "   b. Wait 6-7 minutes for the alarm to trigger"
    echo ""
    echo "   c. Check alarm state:"
    echo "      aws cloudwatch describe-alarms --alarm-names $ALARM_NAME --query 'MetricAlarms[0].StateValue'"
    echo ""
    echo "   d. Check your email ($ALERT_EMAIL) for alert notification"
    echo ""
    echo "   e. Resume heartbeat to verify auto-resolution:"
    echo "      ./start_heartbeat.sh"
    echo ""
    echo "5. CONFIRM SNS SUBSCRIPTION:"
    echo "   Check your email for AWS SNS subscription confirmation"
    echo "   Click the confirmation link to enable notifications"
    echo ""
    echo "---------------------------------------------------"
    echo "TROUBLESHOOTING"
    echo "---------------------------------------------------"
    echo "• View Lambda logs:     aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
    echo "• Check alarm status:   aws cloudwatch describe-alarms --alarm-names $ALARM_NAME"
    echo "• Test function:        curl -X POST $FUNCTION_URL -d '{\"device\":\"test\"}'"
    echo "• View SNS topic:       aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN"
    echo "---------------------------------------------------"
    
else
    echo "Could not determine stack name to retrieve outputs."
fi

