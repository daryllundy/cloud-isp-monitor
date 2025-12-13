# Azure vs AWS Implementation Comparison

This document provides a detailed comparison of the Azure and AWS implementations of the ISP Monitor system.

## Overview

Both implementations provide identical functionality: monitoring internet connectivity by detecting missing heartbeat pings and sending email alerts. The choice between Azure and AWS depends on your existing infrastructure, cloud preferences, and cost considerations.

## Architecture Comparison

### Azure Architecture

```
Device → Azure Function → Application Insights → Azure Monitor Alert → Action Group → Email
```

### AWS Architecture

```
Device → Lambda Function → CloudWatch Logs → CloudWatch Alarm → SNS Topic → Email
```

## Service Mapping

| Component | Azure | AWS | Notes |
|-----------|-------|-----|-------|
| **Serverless Function** | Azure Functions | AWS Lambda | Both Python 3.11, similar performance |
| **HTTP Endpoint** | Function App URL | Lambda Function URL | Both HTTPS-only, public access |
| **Logging** | Application Insights | CloudWatch Logs | Both structured JSON logging |
| **Metrics** | Application Insights Metrics | CloudWatch Metrics (via Metric Filter) | AWS requires explicit metric filter |
| **Alerting** | Azure Monitor Scheduled Query | CloudWatch Alarm | Similar 5-minute evaluation |
| **Notifications** | Action Group | SNS Topic | Both support email subscriptions |
| **Infrastructure as Code** | Bicep | AWS CDK (Python) | Both declarative, CDK more programmatic |
| **Authentication** | Managed Identity | IAM Roles | Both eliminate connection strings |
| **Storage** | Storage Account (required) | None (not needed) | Azure requires storage for function state |

## Feature Comparison

### Deployment

| Feature | Azure | AWS |
|---------|-------|-----|
| **Deployment Tool** | Azure CLI + Bicep | AWS CDK + CloudFormation |
| **Deployment Script** | `deploy.sh` | `deploy_aws.sh` |
| **Bootstrap Required** | No | Yes (first deployment only) |
| **Deployment Time** | 3-5 minutes | 2-4 minutes |
| **Rollback Support** | Yes (via Azure Portal) | Yes (via CloudFormation) |

### Configuration

| Feature | Azure | AWS |
|---------|-------|-----|
| **Environment File** | `.env` | `.env` |
| **Required Variables** | RG, LOCATION, ALERT_EMAIL | AWS_REGION, ALERT_EMAIL, PREFIX |
| **Log Retention** | Fixed (Application Insights) | Configurable (7-365 days) |
| **Memory Configuration** | Fixed (Consumption Plan) | Configurable (128-10240 MB) |

### Monitoring

| Feature | Azure | AWS |
|---------|-------|-----|
| **Log Query Language** | KQL (Kusto) | CloudWatch Logs Insights |
| **Metric Creation** | Automatic | Manual (Metric Filter) |
| **Alert Evaluation** | 5 minutes (minimum) | 5 minutes (configurable) |
| **Alert Resolution** | Automatic | Automatic |
| **Notification Frequency** | Every 5 minutes | Every 5 minutes |

### Security

| Feature | Azure | AWS |
|---------|-------|-----|
| **Function Authentication** | Anonymous (configurable) | None (by design) |
| **Service Authentication** | Managed Identity | IAM Roles |
| **HTTPS Enforcement** | Yes | Yes |
| **Input Validation** | Yes | Yes |
| **Log Encryption** | Yes (default) | Yes (default) |
| **Secrets Management** | Key Vault (optional) | Secrets Manager (optional) |

## Cost Comparison

### Azure Costs (Monthly)

| Service | Free Tier | After Free Tier | Typical Usage |
|---------|-----------|-----------------|---------------|
| Azure Functions | 1M executions | $0.20/M executions | ~43,200 executions |
| Application Insights | 5 GB | $2.30/GB | ~0.05 GB |
| Storage Account | 5 GB | $0.02/GB | ~0.01 GB |
| Azure Monitor Alerts | None | $0.10/alert | 1 alert |
| **Total** | **$0-2** | **$2-10** | **~$2-5/month** |

### AWS Costs (Monthly)

| Service | Free Tier | After Free Tier | Typical Usage |
|---------|-----------|-----------------|---------------|
| Lambda | 1M requests | $0.20/M requests | ~43,200 requests |
| Lambda Compute | 400K GB-sec | $0.0000166667/GB-sec | ~5,400 GB-sec |
| CloudWatch Logs | 5 GB ingestion | $0.50/GB | ~0.05 GB |
| CloudWatch Metrics | None | $0.30/metric | 1 custom metric |
| CloudWatch Alarms | 10 alarms | $0.10/alarm | 1 alarm |
| SNS | 1,000 emails | $2.00/100K emails | ~20 emails |
| **Total** | **$0** | **$0.40-0.50** | **~$0-0.10/month** |

**Winner**: AWS is significantly cheaper (~$0.10/month vs $2-5/month)

## Performance Comparison

### Cold Start Times

| Platform | Cold Start | Warm Execution |
|----------|-----------|----------------|
| Azure Functions (Consumption) | 1-3 seconds | 50-100ms |
| AWS Lambda (ARM64, 128MB) | 500ms-1s | 30-80ms |

**Winner**: AWS Lambda has faster cold starts

### Execution Time

Both platforms execute the heartbeat handler in similar time:
- **Azure**: ~80-120ms average
- **AWS**: ~60-100ms average

**Winner**: Tie (negligible difference)

## Developer Experience

### Infrastructure as Code

**Azure (Bicep)**:
```bicep
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
    }
  }
}
```

**AWS (CDK Python)**:
```python
heartbeat_fn = _lambda.Function(
    self, "HeartbeatHandler",
    runtime=_lambda.Runtime.PYTHON_3_11,
    architecture=_lambda.Architecture.ARM_64,
    handler="handler.lambda_handler",
    code=_lambda.Code.from_asset("../lambda"),
    memory_size=128,
    timeout=Duration.seconds(10),
)
```

**Winner**: Subjective
- Bicep: More concise, Azure-native
- CDK: More programmatic, type-safe, reusable

### Local Development

| Feature | Azure | AWS |
|---------|-------|-----|
| **Local Runtime** | Azure Functions Core Tools | AWS SAM CLI (optional) |
| **Local Testing** | `func start` | Direct Python execution |
| **Debugging** | VS Code integration | VS Code integration |
| **Hot Reload** | Yes | No (restart required) |

**Winner**: Azure (better local development experience)

### Deployment Speed

| Metric | Azure | AWS |
|--------|-------|-----|
| **First Deployment** | 5-7 minutes | 4-6 minutes |
| **Subsequent Deployments** | 2-3 minutes | 2-3 minutes |
| **Code-Only Updates** | 30-60 seconds | 30-60 seconds |

**Winner**: Tie

## Testing Support

### Unit Testing

Both platforms support standard Python unit testing:
- **Azure**: pytest with `azure-functions` library
- **AWS**: pytest with Lambda event mocking

**Winner**: Tie

### Integration Testing

| Feature | Azure | AWS |
|---------|-------|-----|
| **Test Scripts** | `test_alerts.sh`, `diagnose_alerts.sh` | `test_aws_alerts.sh`, `test_alarm_behavior.sh` |
| **E2E Testing** | Manual | Automated (`run_e2e_verification.sh`) |
| **Alarm Testing** | Manual (6+ minute wait) | Automated (pytest integration) |

**Winner**: AWS (better automated testing support)

### Property-Based Testing

Both implementations include comprehensive property-based tests:
- Device name sanitization
- Note sanitization
- IP validation
- Structured logging
- Response format

**Winner**: Tie (identical test coverage)

## Migration Considerations

### Azure → AWS Migration

**Pros**:
- Lower costs (~$0.10/month vs $2-5/month)
- Faster cold starts
- Better automated testing
- No storage account required

**Cons**:
- Need to learn AWS services
- Different IaC tool (CDK vs Bicep)
- Different query language (Logs Insights vs KQL)

**Effort**: 2-4 hours (see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md))

### AWS → Azure Migration

**Pros**:
- Better local development experience
- Simpler IaC (Bicep)
- Integrated monitoring (Application Insights)

**Cons**:
- Higher costs
- Slower cold starts
- Requires storage account

**Effort**: 2-4 hours

## Recommendations

### Choose Azure if:
- You already use Azure for other services
- You prefer Bicep over CDK
- You want better local development tools
- Cost difference ($2-5/month) is acceptable

### Choose AWS if:
- You want minimal costs (~$0.10/month)
- You prefer faster cold starts
- You want better automated testing
- You prefer programmatic IaC (CDK)

### Choose Either if:
- You're new to cloud platforms (both work well)
- You want to learn cloud services (good learning project)
- Cost and performance differences don't matter

## Conclusion

Both implementations are production-ready and provide identical functionality. The choice depends on:

1. **Cost**: AWS is significantly cheaper
2. **Existing Infrastructure**: Use what you already have
3. **Developer Preference**: Both have good tooling
4. **Learning Goals**: Both are good for learning cloud services

For new deployments with no existing cloud infrastructure, **AWS is recommended** due to lower costs and faster performance.

## See Also

- [README.md](../README.md) - Azure deployment guide
- [README_AWS.md](../README_AWS.md) - AWS deployment guide
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Migration instructions
- [SCRIPTS.md](SCRIPTS.md) - Script documentation
