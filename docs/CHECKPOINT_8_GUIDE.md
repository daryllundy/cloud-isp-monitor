# Checkpoint 8: End-to-End Verification Guide

This checkpoint verifies that the complete AWS ISP Monitor system works correctly from deployment through alarm testing.

## Quick Start

Run the interactive verification script:

```bash
./run_e2e_verification.sh
```

This script will guide you through all verification steps automatically.

## What Gets Verified

### Requirements Validated

- **Requirement 3.2**: CloudWatch detects missing heartbeats and triggers alert
- **Requirement 3.3**: Heartbeat resumes and alarm automatically resolves
- **Requirement 4.1**: Email notification sent via SNS when alert triggers
- **Requirement 4.3**: Resolution notification sent when alert resolves

### Verification Steps

1. **Prerequisites Check**
   - AWS CLI installed and authenticated
   - CDK CLI installed
   - Python 3 available
   - `.env` file configured

2. **Infrastructure Deployment**
   - Deploy CDK stack (if not already deployed)
   - Retrieve stack outputs (Function URL, Alarm name, SNS topic)
   - Update `.env` with Function URL

3. **SNS Subscription Confirmation**
   - Check subscription status
   - Prompt to confirm email subscription if pending
   - Verify subscription is active

4. **Test Heartbeat**
   - Send single test heartbeat to Lambda
   - Verify HTTP 200 response
   - Confirm "ok" response body

5. **CloudWatch Logs Verification**
   - Wait for logs to appear (10 seconds)
   - Query recent logs for heartbeat entries
   - Verify structured JSON format

6. **Continuous Heartbeat**
   - Start heartbeat agent in background
   - Wait for alarm to stabilize (2 minutes)
   - Verify agent is running

7. **Alarm OK State**
   - Check alarm reaches OK state
   - Wait up to 5 minutes if in INSUFFICIENT_DATA
   - Confirm alarm is healthy

8. **Alarm Trigger Test**
   - Stop heartbeat agent
   - Wait 7 minutes for alarm to trigger
   - Verify alarm enters ALARM state
   - Confirm ALARM email received

9. **Alarm Resolution Test**
   - Resume heartbeat agent
   - Wait 6 minutes for alarm to resolve
   - Verify alarm returns to OK state
   - Confirm resolution email received

## Manual Verification (Alternative)

If you prefer to verify manually without the script:

### 1. Deploy Infrastructure

```bash
./deploy_aws.sh
```

### 2. Update .env

Add the Function URL from deployment output:

```bash
HEARTBEAT_URL=https://your-function-id.lambda-url.us-east-1.on.aws/
```

### 3. Confirm SNS Subscription

Check your email for AWS SNS confirmation and click the link.

Verify:
```bash
aws sns list-subscriptions-by-topic --topic-arn <your-topic-arn>
```

### 4. Send Test Heartbeat

```bash
python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "test" --once --verbose
```

### 5. Check CloudWatch Logs

```bash
aws logs tail /aws/lambda/<function-name> --follow
```

Look for entries like:
```
[heartbeat] {"ts": 1702345678, "device": "test", "ip": "203.0.113.42", "note": "single ping"}
```

### 6. Start Continuous Heartbeat

```bash
./start_heartbeat.sh
```

Wait 5-6 minutes for alarm to reach OK state.

### 7. Test Alarm Trigger

```bash
./stop_heartbeat.sh
```

Wait 6-7 minutes. Check alarm state:

```bash
aws cloudwatch describe-alarms --alarm-names <alarm-name> --query 'MetricAlarms[0].StateValue'
```

Should return: `"ALARM"`

Check your email for alert notification.

### 8. Test Alarm Resolution

```bash
./start_heartbeat.sh
```

Wait 5-6 minutes. Check alarm state:

```bash
aws cloudwatch describe-alarms --alarm-names <alarm-name> --query 'MetricAlarms[0].StateValue'
```

Should return: `"OK"`

Check your email for resolution notification.

## Success Criteria

All of the following must be true:

- ✅ Infrastructure deploys successfully
- ✅ Test heartbeat returns HTTP 200
- ✅ CloudWatch Logs contain heartbeat entries
- ✅ Alarm reaches OK state with continuous heartbeats
- ✅ SNS subscription is confirmed
- ✅ Alarm triggers when heartbeats stop (6-7 minutes)
- ✅ Email notification received for ALARM state
- ✅ Alarm resolves when heartbeats resume (5-6 minutes)
- ✅ Email notification received for OK state
- ✅ Agent runs continuously without errors

## Troubleshooting

### No Logs in CloudWatch

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
  --dimensions Name=FunctionName,Value=<function-name> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Alarm Not Triggering

**Check:**
- Alarm is enabled
- Alarm configuration (threshold, evaluation period)
- Metric filter is creating metrics
- "Treat missing data" setting is "breaching"

**Commands:**
```bash
# View alarm details
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# Check metric data
aws cloudwatch get-metric-statistics \
  --namespace ISPMonitor \
  --metric-name HeartbeatCount \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Email Not Received

**Check:**
- SNS subscription is confirmed (not pending)
- Check spam folder
- Alarm actions include SNS topic ARN
- SNS topic has email subscription

**Commands:**
```bash
# Check subscription status
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>

# Check alarm actions
aws cloudwatch describe-alarms --alarm-names <alarm-name> \
  --query 'MetricAlarms[0].[AlarmActions,OKActions]'
```

### Agent Connection Errors

**Check:**
- Function URL is correct in `.env`
- Function URL is accessible
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

## Time Requirements

Total time for complete verification: **~20-25 minutes**

- Prerequisites: 2 minutes
- Deployment: 3-5 minutes
- SNS confirmation: 1-2 minutes
- Test heartbeat: 1 minute
- Alarm stabilization: 2-5 minutes
- Alarm trigger test: 7 minutes
- Alarm resolution test: 6 minutes

## Next Steps

After successful verification:

1. ✅ Mark checkpoint task as complete
2. Update `.env` with production device name
3. Configure agent to start on boot (systemd, cron, etc.)
4. Monitor costs in AWS Cost Explorer
5. Set up CloudWatch Dashboard (optional)
6. Document any custom configuration

## Useful Commands

```bash
# View Lambda logs in real-time
aws logs tail /aws/lambda/<function-name> --follow

# Check alarm state
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# Start heartbeat agent
./start_heartbeat.sh

# Stop heartbeat agent
./stop_heartbeat.sh

# Check agent status
tmux capture-pane -pt isp-monitor -S -50

# Test single heartbeat
python3 heartbeat_agent.py --url "$HEARTBEAT_URL" --device "test" --once --verbose
```

## Notes

- First alarm evaluation may take 5-10 minutes after deployment
- SNS email confirmation is required before notifications work
- Alarm state transitions may take 1-2 evaluation periods
- CloudWatch Logs may have 5-10 second delay
- Free tier covers ~43,000 invocations/month (more than enough for 60s interval)

## Related Documentation

- [E2E Verification Checklist](E2E_VERIFICATION_CHECKLIST.md) - Detailed manual checklist
- [README_AWS.md](README_AWS.md) - AWS deployment documentation
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Azure to AWS migration guide
- [deploy_aws.sh](deploy_aws.sh) - Deployment script
- [test_e2e_aws.sh](test_e2e_aws.sh) - Automated E2E test script
