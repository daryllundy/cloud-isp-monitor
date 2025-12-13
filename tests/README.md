# AWS ISP Monitor Tests

This directory contains integration tests for the AWS ISP Monitor system.

## Setup

Install test dependencies:

```bash
pip install -r tests/requirements.txt
```

## Test Files

### test_alarm.py

Integration tests for CloudWatch Alarm behavior.

**Tests:**
- `test_alarm_behavior()` - Full end-to-end alarm test (slow, ~12-15 minutes)
  - Validates Requirement 3.2: Alarm triggers when pings stop
  - Validates Requirement 3.3: Alarm resolves when pings resume
  
- `test_alarm_configuration()` - Verifies alarm configuration
  - Validates Requirement 3.1: 5-minute evaluation window
  - Validates alarm threshold and missing data handling

### test_e2e.py

End-to-end tests for basic functionality.

**Tests:**
- `test_e2e_heartbeat_flow()` - Verifies heartbeat ping and logging

### test_agent_config.py

Unit tests for heartbeat agent configuration.

### test_deployment.py

Tests for deployment scripts and infrastructure.

## Running Tests

### Prerequisites

1. Deploy the AWS stack:
   ```bash
   ./deploy_aws.sh
   ```

2. Configure environment variables in `.env`:
   ```bash
   AWS_REGION=us-east-1
   PREFIX=isp-monitor
   ALERT_EMAIL=your-email@example.com
   HEARTBEAT_URL=https://your-function-id.lambda-url.us-east-1.on.aws/
   ```

3. Enable integration tests:
   ```bash
   export E2E_TEST_ENABLED=1
   ```

### Run All Tests

```bash
pytest tests/
```

### Run Specific Tests

```bash
# Run only alarm tests
pytest tests/test_alarm.py

# Run only the alarm behavior test (slow)
pytest tests/test_alarm.py::test_alarm_behavior -v

# Run only the alarm configuration test (fast)
pytest tests/test_alarm.py::test_alarm_configuration -v

# Run with verbose output
pytest tests/test_alarm.py -v -s
```

### Skip Slow Tests

By default, slow tests (like `test_alarm_behavior`) are skipped unless `E2E_TEST_ENABLED=1` is set:

```bash
# This will skip the alarm behavior test
pytest tests/test_alarm.py

# This will run all tests including slow ones
E2E_TEST_ENABLED=1 pytest tests/test_alarm.py
```

## Test Markers

Tests use pytest markers to categorize them:

- `@pytest.mark.integration` - Integration tests that require deployed infrastructure
- `@pytest.mark.slow` - Tests that take a long time to run (5+ minutes)

### Run Only Fast Tests

```bash
pytest tests/ -m "not slow"
```

### Run Only Integration Tests

```bash
pytest tests/ -m integration
```

## Alarm Behavior Test Details

The `test_alarm_behavior()` test is comprehensive but slow (~12-15 minutes). It:

1. **Phase 1: Establish OK State (6 minutes)**
   - Sends heartbeat pings every 30 seconds
   - Waits for alarm to reach OK state

2. **Phase 2: Trigger Alarm (7 minutes)**
   - Stops sending pings
   - Waits for CloudWatch to detect missing heartbeats
   - Verifies alarm enters ALARM state

3. **Phase 3: Resolve Alarm (6 minutes)**
   - Resumes sending pings
   - Waits for CloudWatch to detect resumed heartbeats
   - Verifies alarm returns to OK state

### Why So Slow?

CloudWatch alarms evaluate metrics at fixed intervals (5 minutes in this case). The test must:
- Wait for at least one evaluation period to establish baseline
- Wait for at least one evaluation period to trigger the alarm
- Wait for at least one evaluation period to resolve the alarm

This is unavoidable when testing real CloudWatch alarm behavior.

## Troubleshooting

### Test Fails: "Stack not found"

Make sure you've deployed the stack:
```bash
./deploy_aws.sh
```

### Test Fails: "FunctionUrl output not found"

Verify your stack has the required outputs:
```bash
aws cloudformation describe-stacks --stack-name IspMonitorStack --query 'Stacks[0].Outputs'
```

### Test Fails: Alarm doesn't trigger

Check CloudWatch alarm configuration:
```bash
aws cloudwatch describe-alarms --alarm-names <alarm-name>
```

Verify logs are being written:
```bash
aws logs tail /aws/lambda/<function-name> --follow
```

### Test Times Out

The alarm behavior test can take 15+ minutes. Make sure:
- You have a stable internet connection
- AWS services are responding normally
- The Lambda function is working correctly

## CI/CD Integration

For CI/CD pipelines, you may want to skip the slow alarm behavior test:

```bash
# Run fast tests only
pytest tests/ -m "not slow"

# Or run alarm configuration test only
pytest tests/test_alarm.py::test_alarm_configuration
```

The full alarm behavior test should be run manually or in a nightly test suite.
