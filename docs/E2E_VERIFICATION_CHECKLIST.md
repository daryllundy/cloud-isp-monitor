# End-to-End Verification Checklist

This checklist guides you through verifying the complete AWS ISP Monitor deployment.

## Prerequisites

Before starting, ensure:

- [ ] AWS infrastructure is deployed (`./deploy_aws.sh` completed successfully)
- [ ] `.env` file contains `HEARTBEAT_URL` from deployment output
- [ ] `.env` file contains `ALERT_EMAIL` 
- [ ] `.env` file contains `AWS_REGION`
- [ ] AWS CLI is authenticated (`aws sts get-caller-identity` works)

## Automated Verification

Run the automated E2E test script:

```bash
./test_e2e_aws.sh
```

This script will:
- Validate prerequisites
- Send a test heartbeat
- Verify CloudWatch Logs
- Check alarm state
- Verify SNS subscription
- Optionally run the full alarm test

## Manual Verification Steps

If you prefer to verify manually, follow these steps:

### Step 1: Deploy Infrastructure

```bash
./deploy_aws.sh
```

**Expected outcome:**
- ✓ CDK deployment succeeds
- ✓ Function URL is displayed
- ✓ Test ping returns HTTP 200

**Verification:**
```bash
# Check stack exists
cd cdk && cdk list

# Get outputs
STACK_NAME=$(cdk list | head -n 1)
aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs"
```

### Step 2: Configure Heartbeat Agent

Update `.env` with the Function URL from deployment:

```bash
HEARTBEAT_URL=https://your-function-id.lambda-url.us-east-1.on.aws/
HEARTBEAT_DEVICE=test-device
HEARTBEAT_INTERVAL=60
```

### Step 3: Send Test Heartbeat

```bash
python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "test-device" --once --verbose
```

**Expected outcome:**
- ✓ Ping sent successfully
- ✓ HTTP 200 response received
- ✓ Response body is "ok"

### Step 4: Verify CloudWatch Logs

Wait 5-10 seconds, then check logs:

```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$(cd cdk && cdk list | head -n 1)" \
  --query 'Stacks[0].Outputs[?OutputKey==`FunctionName`].OutputValue' \
  --output text)

# View recent logs
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

**Expected outcome:**
- ✓ Log entry contains `[heartbeat]`
- ✓ Log entry is valid JSON with fields: `ts`, `device`, `ip`, `note`
- ✓ Device name matches what you sent

**Example log entry:**
```
[heartbeat] {"ts": 1702345678, "device": "test-device", "ip": "203.0.113.42", "note": "single ping"}
```

### Step 5: Check Alarm State

```bash
# Get alarm name from stack outputs
ALARM_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$(cd cdk && cdk list | head -n 1)" \
  --query 'Stacks[0].Outputs[?OutputKey==`AlarmName`].OutputValue' \
  --output text)

# Check alarm state
aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue'
```

**Expected outcome:**
- ✓ Alarm state is `OK` or `INSUFFICIENT_DATA` (normal for new deployments)
- ✓ Alarm configuration shows 5-minute evaluation period
- ✓ Threshold is less than 1 heartbeat

### Step 6: Verify SNS Subscription

```bash
# Get SNS topic ARN
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$(cd cdk && cdk list | head -n 1)" \
  --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' \
  --output text)

# Check subscriptions
aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"
```

**Expected outcome:**
- ✓ Email subscription exists for your alert email
- ✓ Subscription status is `Confirmed` (not `PendingConfirmation`)

**If pending:** Check your email for AWS SNS confirmation and click the link.

### Step 7: Test Alarm Trigger (Stop Heartbeat)

Start the heartbeat agent in the background:

```bash
./start_heartbeat.sh
```

Wait 5-6 minutes for the alarm to reach OK state, then stop it:

```bash
./stop_heartbeat.sh
```

**Wait 6-7 minutes** (alarm evaluates every 5 minutes, plus buffer).

Check alarm state:

```bash
aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue'
```

**Expected outcome:**
- ✓ Alarm state changes from `OK` to `ALARM`
- ✓ Email notification is received at your alert email
- ✓ Email subject mentions "ALARM" and alarm name
- ✓ Email body contains alarm details

### Step 8: Test Alarm Resolution (Resume Heartbeat)

Resume the heartbeat agent:

```bash
./start_heartbeat.sh
```

**Wait 5-6 minutes** for the alarm to resolve.

Check alarm state:

```bash
aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue'
```

**Expected outcome:**
- ✓ Alarm state changes from `ALARM` to `OK`
- ✓ Resolution email notification is received
- ✓ Email subject mentions "OK" and alarm name

### Step 9: Verify Continuous Operation

Let the heartbeat agent run for 15-20 minutes:

```bash
# Check agent is running
tmux capture-pane -pt isp-monitor -S -50

# View CloudWatch Logs
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

**Expected outcome:**
- ✓ Heartbeat logs appear every 60 seconds
- ✓ No errors in agent output
- ✓ Alarm remains in OK state
- ✓ No unexpected email notifications

## Troubleshooting

### No logs appearing in CloudWatch

**Check:**
- Lambda execution role has CloudWatch Logs permissions
- Lambda function is being invoked (check Invocations metric)
- No Lambda errors (check Errors metric)

**Commands:**
```bash
# Check Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Alarm not triggering

**Check:**
- Alarm is enabled
- Alarm configuration (threshold, evaluation period)
- Metric filter is creating metrics
- "Treat missing data" setting is "breaching"

**Commands:**
```bash
# View alarm details
aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME"

# Check metric data
aws cloudwatch get-metric-statistics \
  --namespace ISPMonitor \
  --metric-name HeartbeatCount \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Email notifications not received

**Check:**
- SNS subscription is confirmed (not pending)
- Check spam folder
- Alarm actions include SNS topic ARN
- SNS topic has email subscription

**Commands:**
```bash
# Check subscription status
aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"

# Check alarm actions
aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[0].[AlarmActions,OKActions]'
```

### Agent connection errors

**Check:**
- Function URL is correct in `.env`
- Function URL is accessible (not deleted)
- SSL certificate verification is working
- Network connectivity

**Commands:**
```bash
# Test function URL directly
curl -X POST "$HEARTBEAT_URL" \
  -H "Content-Type: application/json" \
  -d '{"device":"test","note":"manual test"}'

# Test with verbose agent
python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "test" --once --verbose
```

## Success Criteria

All of the following must be true:

- [x] Infrastructure deploys successfully
- [x] Test heartbeat returns HTTP 200
- [x] CloudWatch Logs contain heartbeat entries
- [x] Alarm reaches OK state with continuous heartbeats
- [x] SNS subscription is confirmed
- [x] Alarm triggers when heartbeats stop (6-7 minutes)
- [x] Email notification is received for ALARM state
- [x] Alarm resolves when heartbeats resume (5-6 minutes)
- [x] Email notification is received for OK state
- [x] Agent runs continuously without errors

## Requirements Validated

This checkpoint verifies:

- **Requirement 3.2**: CloudWatch detects missing heartbeats and triggers alert
- **Requirement 3.3**: Heartbeat resumes and alarm automatically resolves
- **Requirement 4.1**: Email notification sent via SNS when alert triggers
- **Requirement 4.3**: Resolution notification sent when alert resolves

## Next Steps

After successful verification:

1. Update `.env` with production device name
2. Configure agent to start on boot (systemd, cron, etc.)
3. Monitor costs in AWS Cost Explorer
4. Set up CloudWatch Dashboard (optional)
5. Document any custom configuration

## Notes

- First alarm evaluation may take 5-10 minutes after deployment
- SNS email confirmation is required before notifications work
- Alarm state transitions may take 1-2 evaluation periods
- CloudWatch Logs may have 5-10 second delay
- Free tier covers ~43,000 invocations/month (more than enough for 60s interval)
