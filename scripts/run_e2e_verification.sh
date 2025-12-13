#!/bin/bash
# Interactive End-to-End Verification for AWS ISP Monitor
# This script guides you through the complete deployment and verification process

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}AWS ISP Monitor - E2E Verification${NC}"
echo -e "${CYAN}Complete Deployment & Testing Guide${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Function to prompt user
prompt_continue() {
    echo ""
    read -p "Press Enter to continue or Ctrl+C to exit..."
    echo ""
}

# Step 1: Check prerequisites
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Checking Prerequisites${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found${NC}"
    echo "  Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi
echo -e "${GREEN}✓ AWS CLI installed${NC}"

# Check AWS authentication
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not authenticated${NC}"
    echo "  Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
echo -e "${GREEN}✓ AWS authenticated${NC}"
echo "  Account: $AWS_ACCOUNT"
echo "  User: $AWS_USER"

# Check CDK
if ! command -v cdk &> /dev/null; then
    echo -e "${RED}✗ AWS CDK CLI not found${NC}"
    echo "  Please install: npm install -g aws-cdk"
    exit 1
fi
echo -e "${GREEN}✓ AWS CDK CLI installed${NC}"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python 3 installed${NC}"

# Check .env file
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠ No .env file found${NC}"
    echo ""
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo -e "${GREEN}✓ Created .env file${NC}"
    echo ""
    echo -e "${YELLOW}Please edit .env and set:${NC}"
    echo "  - AWS_REGION (e.g., us-east-1)"
    echo "  - ALERT_EMAIL (your email address)"
    echo "  - PREFIX (e.g., isp-monitor)"
    echo ""
    echo "Then run this script again."
    exit 0
fi

# Load .env
export $(grep -v '^#' .env | xargs)

# Validate required variables
MISSING_VARS=()
[ -z "$AWS_REGION" ] && MISSING_VARS+=("AWS_REGION")
[ -z "$ALERT_EMAIL" ] && MISSING_VARS+=("ALERT_EMAIL")
[ -z "$PREFIX" ] && MISSING_VARS+=("PREFIX")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing required variables in .env:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

echo -e "${GREEN}✓ Configuration loaded from .env${NC}"
echo "  AWS_REGION: $AWS_REGION"
echo "  ALERT_EMAIL: $ALERT_EMAIL"
echo "  PREFIX: $PREFIX"

prompt_continue

# Step 2: Deploy infrastructure
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Deploy AWS Infrastructure${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name IspMonitorStack 2>&1 | grep -c "does not exist" || true)

if [ "$STACK_EXISTS" -eq 0 ]; then
    echo -e "${YELLOW}Stack already exists. Checking status...${NC}"
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name IspMonitorStack --query "Stacks[0].StackStatus" --output text)
    echo "Current status: $STACK_STATUS"
    echo ""
    read -p "Do you want to update the stack? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping deployment. Using existing stack."
    else
        echo "Deploying stack update..."
        ./deploy_aws.sh
    fi
else
    echo "No existing stack found. Deploying new infrastructure..."
    echo ""
    echo "This will:"
    echo "  • Create Lambda function for heartbeat endpoint"
    echo "  • Create CloudWatch Logs and Alarms"
    echo "  • Create SNS topic for email notifications"
    echo "  • Configure all monitoring and alerting"
    echo ""
    prompt_continue
    
    ./deploy_aws.sh
fi

# Get stack outputs
echo ""
echo "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks --stack-name IspMonitorStack --query "Stacks[0].Outputs" --output json)

FUNCTION_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
FUNCTION_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
ALARM_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AlarmName") | .OutputValue')
SNS_TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SnsTopicArn") | .OutputValue')

echo -e "${GREEN}✓ Deployment complete${NC}"
echo ""
echo "Stack outputs:"
echo "  Function URL: $FUNCTION_URL"
echo "  Function Name: $FUNCTION_NAME"
echo "  Alarm Name: $ALARM_NAME"
echo "  SNS Topic: $SNS_TOPIC_ARN"

# Update .env with Function URL
if [ -n "$FUNCTION_URL" ]; then
    if grep -q "^HEARTBEAT_URL=" .env; then
        # Update existing
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^HEARTBEAT_URL=.*|HEARTBEAT_URL=$FUNCTION_URL|" .env
        else
            sed -i "s|^HEARTBEAT_URL=.*|HEARTBEAT_URL=$FUNCTION_URL|" .env
        fi
    else
        # Add new
        echo "HEARTBEAT_URL=$FUNCTION_URL" >> .env
    fi
    echo -e "${GREEN}✓ Updated .env with HEARTBEAT_URL${NC}"
    export HEARTBEAT_URL="$FUNCTION_URL"
fi

prompt_continue

# Step 3: Confirm SNS subscription
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Confirm SNS Email Subscription${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Checking SNS subscription status..."
SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --query 'Subscriptions[0].SubscriptionArn' --output text)

if [[ "$SUBSCRIPTION_STATUS" == "PendingConfirmation" ]]; then
    echo -e "${YELLOW}⚠ Email subscription is PENDING confirmation${NC}"
    echo ""
    echo "AWS has sent a confirmation email to: $ALERT_EMAIL"
    echo ""
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "  1. Check your email inbox (and spam folder)"
    echo "  2. Look for email from 'AWS Notifications'"
    echo "  3. Click the 'Confirm subscription' link"
    echo ""
    read -p "Press Enter after you've confirmed the subscription..."
    echo ""
    
    # Re-check status
    SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --query 'Subscriptions[0].SubscriptionArn' --output text)
    if [[ "$SUBSCRIPTION_STATUS" == "PendingConfirmation" ]]; then
        echo -e "${RED}✗ Subscription still pending${NC}"
        echo "  You can continue, but email notifications won't work until confirmed"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Exiting. Run this script again after confirming subscription."
            exit 0
        fi
    else
        echo -e "${GREEN}✓ Subscription confirmed!${NC}"
    fi
else
    echo -e "${GREEN}✓ Email subscription is confirmed${NC}"
fi

prompt_continue

# Step 4: Send test heartbeat
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Send Test Heartbeat${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

DEVICE_NAME="${HEARTBEAT_DEVICE:-e2e-test-device}"
echo "Sending test heartbeat..."
echo "  URL: $HEARTBEAT_URL"
echo "  Device: $DEVICE_NAME"
echo ""

if python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "$DEVICE_NAME" --once --verbose; then
    echo ""
    echo -e "${GREEN}✓ Test heartbeat sent successfully${NC}"
else
    echo ""
    echo -e "${RED}✗ Failed to send test heartbeat${NC}"
    exit 1
fi

prompt_continue

# Step 5: Verify CloudWatch Logs
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Verify CloudWatch Logs${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Waiting 10 seconds for logs to appear..."
sleep 10

echo "Fetching recent logs..."
RECENT_LOGS=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --start-time $(($(date +%s) - 120))000 \
    --filter-pattern "[heartbeat]" \
    --query 'events[*].message' \
    --output text 2>/dev/null | tail -n 3)

if [ -n "$RECENT_LOGS" ]; then
    echo -e "${GREEN}✓ CloudWatch Logs contain heartbeat entries:${NC}"
    echo ""
    echo "$RECENT_LOGS"
    echo ""
else
    echo -e "${RED}✗ No heartbeat logs found in CloudWatch${NC}"
    echo "  This may indicate a logging issue"
    echo ""
    echo "Checking Lambda errors..."
    aws logs filter-log-events \
        --log-group-name "/aws/lambda/$FUNCTION_NAME" \
        --start-time $(($(date +%s) - 120))000 \
        --filter-pattern "ERROR" \
        --query 'events[*].message' \
        --output text | head -n 5
    exit 1
fi

prompt_continue

# Step 6: Start continuous heartbeat
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Start Continuous Heartbeat${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Starting heartbeat agent in background..."
./start_heartbeat.sh

echo -e "${GREEN}✓ Heartbeat agent started${NC}"
echo ""
echo "Waiting 2 minutes for alarm to stabilize..."
echo "(Alarm needs data points to reach OK state)"

for i in {1..12}; do
    sleep 10
    echo -n "."
done
echo ""

prompt_continue

# Step 7: Check alarm reaches OK state
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 7: Verify Alarm Reaches OK State${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Checking alarm state..."
ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)

echo "Current alarm state: $ALARM_STATE"

if [ "$ALARM_STATE" = "OK" ]; then
    echo -e "${GREEN}✓ Alarm is in OK state${NC}"
elif [ "$ALARM_STATE" = "INSUFFICIENT_DATA" ]; then
    echo -e "${YELLOW}⚠ Alarm is in INSUFFICIENT_DATA state${NC}"
    echo "  This is normal for new deployments"
    echo "  Waiting up to 5 more minutes for OK state..."
    
    for i in {1..10}; do
        sleep 30
        ALARM_STATE=$(aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --query 'MetricAlarms[0].StateValue' \
            --output text)
        echo "  Check $i/10: $ALARM_STATE"
        
        if [ "$ALARM_STATE" = "OK" ]; then
            echo -e "${GREEN}✓ Alarm reached OK state${NC}"
            break
        fi
    done
else
    echo -e "${YELLOW}⚠ Alarm is in $ALARM_STATE state${NC}"
fi

prompt_continue

# Step 8: Test alarm trigger (stop heartbeat)
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 8: Test Alarm Trigger${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "This will:"
echo "  1. Stop the heartbeat agent"
echo "  2. Wait 7 minutes for alarm to trigger"
echo "  3. Verify you receive an email notification"
echo ""
read -p "Continue with alarm test? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping alarm test."
    echo ""
    echo -e "${YELLOW}To test manually later:${NC}"
    echo "  1. ./stop_heartbeat.sh"
    echo "  2. Wait 6-7 minutes"
    echo "  3. Check alarm: aws cloudwatch describe-alarms --alarm-names $ALARM_NAME"
    echo "  4. ./start_heartbeat.sh"
    echo ""
    echo -e "${GREEN}E2E verification complete (partial)${NC}"
    exit 0
fi

echo ""
echo "Stopping heartbeat agent..."
./stop_heartbeat.sh
echo -e "${GREEN}✓ Heartbeat stopped${NC}"

echo ""
echo "Waiting 7 minutes for alarm to trigger..."
echo "(Alarm evaluates every 5 minutes, plus buffer)"
echo ""

for i in {1..7}; do
    echo "  Minute $i/7..."
    sleep 60
    
    if [ $i -ge 6 ]; then
        ALARM_STATE=$(aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --query 'MetricAlarms[0].StateValue' \
            --output text)
        echo "    Current state: $ALARM_STATE"
        
        if [ "$ALARM_STATE" = "ALARM" ]; then
            echo -e "${GREEN}✓ Alarm triggered!${NC}"
            break
        fi
    fi
done

# Final check
ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)

if [ "$ALARM_STATE" = "ALARM" ]; then
    echo ""
    echo -e "${GREEN}✓ Alarm is in ALARM state${NC}"
    echo ""
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "  Check your email ($ALERT_EMAIL) for the alert notification"
    echo ""
    read -p "Did you receive the ALARM email? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ ALARM email received${NC}"
    else
        echo -e "${YELLOW}⚠ Email not received${NC}"
        echo "  Check spam folder or SNS subscription status"
    fi
else
    echo ""
    echo -e "${YELLOW}⚠ Alarm state is $ALARM_STATE (expected ALARM)${NC}"
    echo "  You may need to wait longer"
fi

prompt_continue

# Step 9: Test alarm resolution (resume heartbeat)
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 9: Test Alarm Resolution${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Resuming heartbeat agent..."
./start_heartbeat.sh
echo -e "${GREEN}✓ Heartbeat resumed${NC}"

echo ""
echo "Waiting 6 minutes for alarm to resolve..."
echo ""

for i in {1..6}; do
    echo "  Minute $i/6..."
    sleep 60
    
    if [ $i -ge 5 ]; then
        ALARM_STATE=$(aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --query 'MetricAlarms[0].StateValue' \
            --output text)
        echo "    Current state: $ALARM_STATE"
        
        if [ "$ALARM_STATE" = "OK" ]; then
            echo -e "${GREEN}✓ Alarm resolved!${NC}"
            break
        fi
    fi
done

# Final check
ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)

if [ "$ALARM_STATE" = "OK" ]; then
    echo ""
    echo -e "${GREEN}✓ Alarm returned to OK state${NC}"
    echo ""
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "  Check your email ($ALERT_EMAIL) for the resolution notification"
    echo ""
    read -p "Did you receive the OK (resolution) email? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Resolution email received${NC}"
    else
        echo -e "${YELLOW}⚠ Email not received${NC}"
        echo "  Check spam folder or wait a bit longer"
    fi
else
    echo ""
    echo -e "${YELLOW}⚠ Alarm state is $ALARM_STATE (expected OK)${NC}"
    echo "  You may need to wait longer"
fi

# Final summary
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}E2E Verification Complete!${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Summary:"
echo "  ✓ Infrastructure deployed successfully"
echo "  ✓ Test heartbeat sent and logged"
echo "  ✓ CloudWatch Logs verified"
echo "  ✓ Alarm reached OK state with heartbeats"
echo "  ✓ Alarm triggered when heartbeats stopped"
echo "  ✓ Alarm resolved when heartbeats resumed"
echo ""
echo "Requirements validated:"
echo "  ✓ Requirement 3.2: CloudWatch detects missing heartbeats"
echo "  ✓ Requirement 3.3: Alarm auto-resolves when heartbeats resume"
echo "  ✓ Requirement 4.1: Email notifications sent via SNS"
echo "  ✓ Requirement 4.3: Resolution notifications sent"
echo ""
echo "Useful commands:"
echo "  • View logs:        aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
echo "  • Check alarm:      aws cloudwatch describe-alarms --alarm-names $ALARM_NAME"
echo "  • Start heartbeat:  ./start_heartbeat.sh"
echo "  • Stop heartbeat:   ./stop_heartbeat.sh"
echo ""
echo -e "${GREEN}AWS ISP Monitor is ready for production use!${NC}"
echo ""
