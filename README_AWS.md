# ISP Monitor on AWS

This guide describes how to deploy the ISP Monitor infrastructure on Amazon Web Services (AWS) using the AWS Cloud Development Kit (CDK).

## Architecture

The AWS implementation uses serverless components to minimize costs and maintenance:

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Your Device    │         │  Lambda Function │         │ CloudWatch      │
│  (home-server)  │  POST   │  (Python 3.11)   │  Logs   │ Logs            │
│                 │────────>│  ARM64, 128MB    │────────>│ (7 day retain)  │
│  heartbeat_     │  HTTPS  │  Function URL    │         │                 │
│  agent.py       │         └──────────────────┘         └────────┬────────┘
└─────────────────┘                                               │
                                                                  │ Metric Filter
                                                                  v
                                                         ┌─────────────────┐
                                                         │ CloudWatch      │
                                                         │ Alarm           │
                                                         │ (5min window)   │
                                                         └────────┬────────┘
                                                                  │
                                                                  v
                                                         ┌─────────────────┐
                                                         │ SNS Topic       │
                                                         │ (Email Alert)   │
                                                         └─────────────────┘
```

### Components

1.  **Lambda Function**: A Python-based Lambda function acts as the heartbeat endpoint. It receives pings from the agent and logs them.
    *   **Runtime**: Python 3.11
    *   **Architecture**: ARM64 (for cost efficiency)
    *   **Memory**: 128 MB (minimum, sufficient for this workload)
    *   **Access**: Public Function URL (HTTPS)
2.  **CloudWatch Logs**: Stores all heartbeat logs (structured JSON).
    *   **Retention**: 7 days (configurable)
3.  **CloudWatch Metrics**: A Metric Filter extracts `HeartbeatCount` from the logs.
4.  **CloudWatch Alarm**: Monitors the `HeartbeatCount` metric.
    *   **Threshold**: Triggers if sum < 1 for 5 minutes.
    *   **Missing Data**: Treated as BREACHING (triggers alarm if pings stop).
5.  **SNS Topic**: Sends notifications when the alarm changes state (ALARM or OK).
    *   **Subscription**: Email (configured during deployment).

## Prerequisites

*   AWS Subscription
*   AWS CLI installed and configured (`aws configure`)
*   Node.js and npm (for CDK CLI)
*   Python 3.8+ (for CDK app)
*   AWS CDK CLI installed (`npm install -g aws-cdk`)

## Deployment

1.  **Clone the repository** (if not already done).

2.  **Configuration**:
    Copy `.env.example` to `.env` in the root directory and update the values:
    ```bash
    cp .env.example .env
    # Edit .env
    AWS_REGION=us-east-1
    ALERT_EMAIL=your.email@example.com
    PREFIX=IspMonitor
    ```

3.  **Run the Deployment Script**:
    The included script handles dependency installation and deployment.
    ```bash
    ./deploy_aws.sh
    ```

4.  **Note the Outputs**:
    After deployment, the script will output the **Function URL**. You will need this to configure the agent.

## Cost Estimation

*   **Lambda**: 43,200 requests/month (1 ping/min). Well within the **AWS Free Tier** (1M requests/month). Without Free Tier, approx $0.01/month.
*   **CloudWatch Logs**: Minimal ingestion (< 100MB/month). Within Free Tier (5GB).
*   **CloudWatch Alarms**: 1 alarm. Standard resolution ($0.10/month). Free Tier offers 10 alarms.
*   **SNS**: Email notifications. Free Tier offers 1,000 emails/month.

**Total Estimated Cost**: **$0.00 - $0.10 / month**

### CloudWatch Cost Optimization

The current configuration is optimized for minimal costs:

**Log Retention**: Set to **7 days** (configurable)
- Reduces storage costs while maintaining recent history
- Sufficient for troubleshooting and debugging
- Can be adjusted via `LOG_RETENTION_DAYS` environment variable in `.env`
- Supported values: 1, 3, 5, 7, 14, 30, 60, 90, 180, 365 days

**Metric Filters vs. Logs Insights**:
- Current implementation uses **Metric Filters** to create custom metrics
- **Cost**: Metric filters are free; custom metrics cost $0.30/metric/month
- **Alternative**: CloudWatch Logs Insights queries (no custom metrics)
  - Queries cost $0.005 per GB scanned
  - For this workload: ~50 MB/month = $0.00025/month
  - **Recommendation**: Current metric filter approach is cost-effective

**Cost Breakdown** (after Free Tier expires):
- Log Ingestion: $0.50/GB → ~$0.025/month (50 MB)
- Log Storage: $0.03/GB → ~$0.0015/month (7 days retention)
- Custom Metric: $0.30/month (HeartbeatCount)
- Alarm: $0.10/month (standard resolution)
- **Total**: ~$0.43/month

**Optimization Tips**:
1. Keep log retention at 7 days (default) unless longer history is needed
2. Use metric filters (current approach) rather than Logs Insights for alarms
3. Avoid creating additional custom metrics
4. Consider using composite alarms only if monitoring multiple metrics

## Testing

### Quick Verification

After deployment, you can verify the system is working:

```bash
# Send a test heartbeat
python3 heartbeat_agent.py --url $HEARTBEAT_URL --device test-device --once --verbose

# Check CloudWatch Logs
aws logs tail /aws/lambda/<function-name> --follow
```

### Integration Tests

The project includes comprehensive integration tests to verify alarm behavior:

```bash
# Install test dependencies
pip install -r tests/requirements.txt

# Run alarm configuration test (fast)
E2E_TEST_ENABLED=1 pytest tests/test_alarm.py::test_alarm_configuration -v

# Run full alarm behavior test (slow, ~12-15 minutes)
./test_alarm_behavior.sh
```

The alarm behavior test verifies:
- **Requirement 3.2**: Alarm triggers when heartbeat pings stop
- **Requirement 3.3**: Alarm automatically resolves when pings resume

See `tests/README.md` for detailed testing documentation.

## Performance and Optimization

### Lambda Memory Configuration

The Lambda function is configured with **128 MB of memory**, which is the minimum allowed by AWS. This is sufficient for the heartbeat handler because:

- The function performs simple operations: JSON parsing, string sanitization, and logging
- No external dependencies or heavy libraries are loaded
- Typical memory usage is 40-60 MB during execution
- Average execution time is under 100ms

**Memory Usage Analysis**:
- **Allocated**: 128 MB
- **Typical Usage**: 40-60 MB (30-47% utilization)
- **Peak Usage**: ~70 MB (55% utilization)

The 128 MB configuration provides adequate headroom while minimizing costs. Increasing memory allocation would:
- Provide faster CPU (AWS scales CPU with memory)
- Increase costs proportionally
- Offer no practical benefit for this simple workload

**Cost Impact**: At 128 MB, the function costs approximately $0.0000002 per invocation (after Free Tier). Doubling to 256 MB would double the cost with no performance benefit for this use case.

## Troubleshooting

*   **Deployment fails**: specific error messages are usually provided by CloudFormation. Check the AWS Console > CloudFormation > StackEvents.
*   **No alarm**: Verify the agent is sending pings (check Agent logs). Validate the Function URL.
*   **Email not received**: Check your spam folder. Ensure you confirmed the SNS subscription (AWS sends a confirmation email initially).

## Documentation

- [README.md](README.md) - Main documentation (Azure)
- [docs/MIGRATION_GUIDE.md](docs/MIGRATION_GUIDE.md) - Azure to AWS migration guide
- [docs/PLATFORM_COMPARISON.md](docs/PLATFORM_COMPARISON.md) - Detailed Azure vs AWS comparison
- [docs/SCRIPTS.md](docs/SCRIPTS.md) - All helper scripts documentation
- [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md) - Security analysis and review
- [docs/AGENT_README.md](docs/AGENT_README.md) - Heartbeat agent documentation
- [tests/README.md](tests/README.md) - Testing documentation

## See Also

- [AWS Lambda Python Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
