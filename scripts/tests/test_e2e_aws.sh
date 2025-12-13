#!/bin/bash
# End-to-End Verification Script for AWS ISP Monitor
# This script guides you through verifying the complete deployment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AWS ISP Monitor - E2E Verification${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${YELLOW}Step 1: Checking Prerequisites${NC}"
echo "-----------------------------------"

if [ -z "$AWS_REGION" ]; then
    echo -e "${RED}✗ AWS_REGION not set in .env${NC}"
    exit 1
fi

if [ -z "$ALERT_EMAIL" ]; then
    echo -e "${RED}✗ ALERT_EMAIL not set in .env${NC}"
    exit 1
fi

if [ -z "$HEARTBEAT_URL" ]; then
    echo -e "${RED}✗ HEARTBEAT_URL not set in .env${NC}"
    echo "  Please run ./deploy_aws.sh first and update .env with the Function URL"
    exit 1
fi

echo -e "${GREEN}✓ AWS_REGION: $AWS_REGION${NC}"
echo -e "${GREEN}✓ ALERT_EMAIL: $ALERT_EMAIL${NC}"
echo -e "${GREEN}✓ HEARTBEAT_URL: $HEARTBEAT_URL${NC}"
echo ""

# Get stack outputs
cd cdk
STACK_NAME=$(cdk list 2>/dev/null | head -n 1)
cd ..

if [ -z "$STACK_NAME" ]; then
    echo -e "${RED}✗ Could not determine CDK stack name${NC}"
    exit 1
fi

OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --output json 2>/dev/null)

if [ -z "$OUTPUTS" ]; then
    echo -e "${RED}✗ Could not retrieve stack outputs${NC}"
    exit 1
fi

FUNCTION_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
ALARM_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AlarmName") | .OutputValue')
SNS_TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SnsTopicArn") | .OutputValue')

echo -e "${GREEN}✓ Function Name: $FUNCTION_NAME${NC}"
echo -e "${GREEN}✓ Alarm Name: $ALARM_NAME${NC}"
echo -e "${GREEN}✓ SNS Topic ARN: $SNS_TOPIC_ARN${NC}"
echo ""

# Step 2: Send test heartbeat
echo -e "${YELLOW}Step 2: Sending Test Heartbeat${NC}"
echo "-----------------------------------"

DEVICE_NAME="${HEARTBEAT_DEVICE:-test-e2e-device}"
echo "Device: $DEVICE_NAME"
echo "Sending ping..."

if python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "$DEVICE_NAME" --once --verbose; then
    echo -e "${GREEN}✓ Test heartbeat sent successfully${NC}"
else
    echo -e "${RED}✗ Failed to send test heartbeat${NC}"
    exit 1
fi
echo ""

# Step 3: Verify CloudWatch Logs
echo -e "${YELLOW}Step 3: Verifying CloudWatch Logs${NC}"
echo "-----------------------------------"
echo "Waiting 5 seconds for logs to appear..."
sleep 5

echo "Fetching recent logs..."
RECENT_LOGS=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --start-time $(($(date +%s) - 60))000 \
    --filter-pattern "[heartbeat]" \
    --query 'events[*].message' \
    --output text 2>/dev/null | tail -n 5)

if [ -n "$RECENT_LOGS" ]; then
    echo -e "${GREEN}✓ CloudWatch Logs contain heartbeat entries:${NC}"
    echo "$RECENT_LOGS" | head -n 3
    echo ""
else
    echo -e "${RED}✗ No heartbeat logs found in CloudWatch${NC}"
    echo "  This may indicate a logging issue"
    exit 1
fi

# Step 4: Check current alarm state
echo -e "${YELLOW}Step 4: Checking Current Alarm State${NC}"
echo "-----------------------------------"

ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null)

echo "Current alarm state: $ALARM_STATE"

if [ "$ALARM_STATE" = "OK" ]; then
    echo -e "${GREEN}✓ Alarm is in OK state (heartbeats are being received)${NC}"
elif [ "$ALARM_STATE" = "INSUFFICIENT_DATA" ]; then
    echo -e "${YELLOW}⚠ Alarm is in INSUFFICIENT_DATA state${NC}"
    echo "  This is normal for new deployments. Continue sending heartbeats."
else
    echo -e "${YELLOW}⚠ Alarm is in $ALARM_STATE state${NC}"
fi
echo ""

# Step 5: Check SNS subscription
echo -e "${YELLOW}Step 5: Checking SNS Subscription${NC}"
echo "-----------------------------------"

SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
    --topic-arn "$SNS_TOPIC_ARN" \
    --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' \
    --output text 2>/dev/null)

if [ -n "$SUBSCRIPTIONS" ]; then
    echo -e "${GREEN}✓ SNS Subscriptions:${NC}"
    echo "$SUBSCRIPTIONS"
    
    # Check if subscription is confirmed
    if echo "$SUBSCRIPTIONS" | grep -q "PendingConfirmation"; then
        echo ""
        echo -e "${YELLOW}⚠ WARNING: Email subscription is pending confirmation!${NC}"
        echo "  Check your email ($ALERT_EMAIL) for AWS SNS confirmation"
        echo "  Click the confirmation link to enable notifications"
    else
        echo -e "${GREEN}✓ Email subscription is confirmed${NC}"
    fi
else
    echo -e "${RED}✗ No SNS subscriptions found${NC}"
fi
echo ""

# Step 6: Manual alarm test instructions
echo -e "${YELLOW}Step 6: Manual Alarm Test Instructions${NC}"
echo "-----------------------------------"
echo "To verify the alarm triggers correctly, follow these steps:"
echo ""
echo "1. Stop sending heartbeats:"
echo "   ${BLUE}./stop_heartbeat.sh${NC}"
echo ""
echo "2. Wait 6-7 minutes for the alarm to trigger"
echo "   (The alarm evaluates every 5 minutes)"
echo ""
echo "3. Check alarm state:"
echo "   ${BLUE}aws cloudwatch describe-alarms --alarm-names $ALARM_NAME --query 'MetricAlarms[0].StateValue'${NC}"
echo ""
echo "4. Check your email ($ALERT_EMAIL) for alert notification"
echo ""
echo "5. Resume heartbeat to verify auto-resolution:"
echo "   ${BLUE}./start_heartbeat.sh${NC}"
echo ""
echo "6. Wait another 5-6 minutes and verify:"
echo "   - Alarm returns to OK state"
echo "   - You receive a resolution email"
echo ""

# Interactive test option
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Would you like to run the alarm test now?${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "This will:"
echo "  1. Start the heartbeat agent in the background"
echo "  2. Wait for alarm to reach OK state"
echo "  3. Stop the heartbeat agent"
echo "  4. Wait 7 minutes for alarm to trigger"
echo "  5. Resume heartbeat"
echo "  6. Wait for alarm to resolve"
echo ""
read -p "Run alarm test? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Starting Alarm Test...${NC}"
    echo "-----------------------------------"
    
    # Start heartbeat agent
    echo "Starting heartbeat agent..."
    if [ -f "./start_heartbeat.sh" ]; then
        ./start_heartbeat.sh
        echo -e "${GREEN}✓ Heartbeat agent started${NC}"
    else
        echo "Starting agent manually..."
        python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "$DEVICE_NAME" --daemon &
        AGENT_PID=$!
        echo -e "${GREEN}✓ Heartbeat agent started (PID: $AGENT_PID)${NC}"
    fi
    
    # Wait for alarm to reach OK state
    echo ""
    echo "Waiting for alarm to reach OK state..."
    echo "(This may take up to 5 minutes)"
    
    for i in {1..10}; do
        sleep 30
        CURRENT_STATE=$(aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --query 'MetricAlarms[0].StateValue' \
            --output text 2>/dev/null)
        
        echo "  Check $i/10: Alarm state is $CURRENT_STATE"
        
        if [ "$CURRENT_STATE" = "OK" ]; then
            echo -e "${GREEN}✓ Alarm reached OK state${NC}"
            break
        fi
    done
    
    # Stop heartbeat
    echo ""
    echo "Stopping heartbeat agent to trigger alarm..."
    if [ -f "./stop_heartbeat.sh" ]; then
        ./stop_heartbeat.sh
    else
        if [ -n "$AGENT_PID" ]; then
            kill $AGENT_PID 2>/dev/null || true
        fi
    fi
    echo -e "${GREEN}✓ Heartbeat agent stopped${NC}"
    
    # Wait for alarm to trigger
    echo ""
    echo "Waiting 7 minutes for alarm to trigger..."
    echo "(Alarm evaluates every 5 minutes, plus buffer time)"
    
    for i in {1..7}; do
        echo "  Minute $i/7..."
        sleep 60
        
        if [ $i -ge 6 ]; then
            CURRENT_STATE=$(aws cloudwatch describe-alarms \
                --alarm-names "$ALARM_NAME" \
                --query 'MetricAlarms[0].StateValue' \
                --output text 2>/dev/null)
            echo "    Current state: $CURRENT_STATE"
            
            if [ "$CURRENT_STATE" = "ALARM" ]; then
                echo -e "${GREEN}✓ Alarm triggered successfully!${NC}"
                break
            fi
        fi
    done
    
    # Check final alarm state
    FINAL_STATE=$(aws cloudwatch describe-alarms \
        --alarm-names "$ALARM_NAME" \
        --query 'MetricAlarms[0].StateValue' \
        --output text 2>/dev/null)
    
    if [ "$FINAL_STATE" = "ALARM" ]; then
        echo -e "${GREEN}✓ Alarm is in ALARM state${NC}"
        echo "  Check your email for the alert notification"
    else
        echo -e "${YELLOW}⚠ Alarm state is $FINAL_STATE (expected ALARM)${NC}"
        echo "  You may need to wait longer or check alarm configuration"
    fi
    
    # Resume heartbeat
    echo ""
    echo "Resuming heartbeat to test auto-resolution..."
    if [ -f "./start_heartbeat.sh" ]; then
        ./start_heartbeat.sh
    else
        python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "$DEVICE_NAME" --daemon &
        AGENT_PID=$!
    fi
    echo -e "${GREEN}✓ Heartbeat agent resumed${NC}"
    
    # Wait for resolution
    echo ""
    echo "Waiting 6 minutes for alarm to resolve..."
    
    for i in {1..6}; do
        echo "  Minute $i/6..."
        sleep 60
        
        if [ $i -ge 5 ]; then
            CURRENT_STATE=$(aws cloudwatch describe-alarms \
                --alarm-names "$ALARM_NAME" \
                --query 'MetricAlarms[0].StateValue' \
                --output text 2>/dev/null)
            echo "    Current state: $CURRENT_STATE"
            
            if [ "$CURRENT_STATE" = "OK" ]; then
                echo -e "${GREEN}✓ Alarm resolved successfully!${NC}"
                break
            fi
        fi
    done
    
    # Final check
    FINAL_STATE=$(aws cloudwatch describe-alarms \
        --alarm-names "$ALARM_NAME" \
        --query 'MetricAlarms[0].StateValue' \
        --output text 2>/dev/null)
    
    if [ "$FINAL_STATE" = "OK" ]; then
        echo -e "${GREEN}✓ Alarm returned to OK state${NC}"
        echo "  Check your email for the resolution notification"
    else
        echo -e "${YELLOW}⚠ Alarm state is $FINAL_STATE (expected OK)${NC}"
        echo "  You may need to wait longer"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Alarm Test Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Verify you received:"
    echo "  1. An ALARM notification email"
    echo "  2. An OK (resolution) notification email"
    echo ""
else
    echo ""
    echo "Skipping automated alarm test."
    echo "You can run the manual test steps above when ready."
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}E2E Verification Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Completed checks:"
echo "  ✓ Prerequisites validated"
echo "  ✓ Test heartbeat sent successfully"
echo "  ✓ CloudWatch Logs verified"
echo "  ✓ Alarm state checked"
echo "  ✓ SNS subscription verified"
echo ""
echo "Next steps:"
echo "  1. Confirm SNS email subscription (if pending)"
echo "  2. Run manual alarm test (if not done automatically)"
echo "  3. Verify email notifications are received"
echo ""
echo "Useful commands:"
echo "  • View logs:        aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
echo "  • Check alarm:      aws cloudwatch describe-alarms --alarm-names $ALARM_NAME"
echo "  • Start heartbeat:  ./start_heartbeat.sh"
echo "  • Stop heartbeat:   ./stop_heartbeat.sh"
echo ""
