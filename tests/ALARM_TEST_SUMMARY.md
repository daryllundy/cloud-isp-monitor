# Alarm Behavior Test Implementation Summary

## Task 9.2: Write alarm behavior test

This document summarizes the implementation of the CloudWatch Alarm behavior test for the AWS ISP Monitor system.

## Requirements Validated

- **Requirement 3.2**: WHEN no heartbeat pings are detected within the window THEN the system SHALL trigger an alert
- **Requirement 3.3**: WHEN heartbeat pings resume THEN the system SHALL automatically resolve the alert

## Files Created

### 1. `tests/test_alarm.py`

Main test file containing two integration tests:

#### `test_alarm_behavior()` (Slow Test)
- **Duration**: ~12-15 minutes
- **Purpose**: End-to-end verification of alarm trigger and resolution
- **Phases**:
  1. **Establish OK State** (6 minutes): Sends pings every 30 seconds to establish baseline
  2. **Trigger Alarm** (7 minutes): Stops pings and waits for alarm to enter ALARM state
  3. **Resolve Alarm** (6 minutes): Resumes pings and waits for alarm to return to OK state
- **Validates**: Requirements 3.2 and 3.3

#### `test_alarm_configuration()`
- **Duration**: < 1 minute
- **Purpose**: Verifies CloudWatch Alarm configuration
- **Checks**:
  - Evaluation period is 5 minutes (300 seconds)
  - Threshold is less than 1 heartbeat
  - Missing data is treated as breaching
  - Alarm actions are enabled
- **Validates**: Requirements 3.1 and 3.2

### 2. `tests/requirements.txt`

Test dependencies:
- `pytest==8.4.2` - Testing framework
- `boto3>=1.34.0` - AWS SDK for Python
- `requests>=2.31.0` - HTTP library for sending test pings

### 3. `tests/README.md`

Comprehensive documentation covering:
- Test setup and prerequisites
- How to run tests
- Test markers and filtering
- Detailed explanation of alarm behavior test
- Troubleshooting guide
- CI/CD integration recommendations

### 4. `test_alarm_behavior.sh`

Convenience script for running the alarm behavior test:
- Checks prerequisites (AWS configuration, stack deployment)
- Installs dependencies if needed
- Provides clear warnings about test duration
- Asks for user confirmation before running
- Displays helpful output and error messages

### 5. `tests/ALARM_TEST_SUMMARY.md`

This document - implementation summary and usage guide.

## Usage

### Quick Start

```bash
# Run the alarm behavior test
./test_alarm_behavior.sh
```

### Manual Execution

```bash
# Install dependencies
pip install -r tests/requirements.txt

# Set environment variables
export E2E_TEST_ENABLED=1
export AWS_REGION=us-east-1
export PREFIX=isp-monitor

# Run the test
pytest tests/test_alarm.py::test_alarm_behavior -v -s
```

### Run Only Configuration Test (Fast)

```bash
E2E_TEST_ENABLED=1 pytest tests/test_alarm.py::test_alarm_configuration -v
```

## Test Design

### Why So Slow?

CloudWatch alarms evaluate metrics at fixed intervals (5 minutes for this system). To properly test alarm behavior, we must:

1. Wait for at least one evaluation period to establish a baseline (OK state)
2. Wait for at least one evaluation period after stopping pings (ALARM state)
3. Wait for at least one evaluation period after resuming pings (OK state)

This results in a minimum test duration of ~15 minutes, which is unavoidable when testing real CloudWatch alarm behavior.

### Test Reliability

The test includes:
- Multiple ping attempts with error handling
- Polling for alarm state changes with timeouts
- Clear phase separation and progress reporting
- Detailed logging of alarm state transitions
- Verification of alarm history timestamps

### CI/CD Considerations

For CI/CD pipelines, consider:
- Running only the fast configuration test in PR checks
- Running the full alarm behavior test in nightly builds
- Using the `@pytest.mark.slow` marker to filter tests

```bash
# Fast tests only (for PR checks)
pytest tests/ -m "not slow"

# All tests (for nightly builds)
E2E_TEST_ENABLED=1 pytest tests/
```

## Test Output Example

```
========================================
Starting Alarm Behavior Test
========================================
Device ID: test-alarm-a1b2c3d4
Function URL: https://xyz.lambda-url.us-east-1.on.aws/
Alarm Name: isp-monitor-heartbeat-missing
========================================

Phase 1: Establishing OK state...
------------------------------------------------------------
  ✓ Sent ping 1
  ✓ Sent ping 2
  ...
  ✓ Sent ping 12

Sent 12 pings over 6 minutes
Waiting 60 seconds for alarm evaluation...
Current alarm state: OK
✓ Phase 1 complete: Alarm is in acceptable state

Phase 2: Stopping pings to trigger alarm...
------------------------------------------------------------
Waiting 7 minutes for alarm to trigger...
(CloudWatch evaluates every 5 minutes)
  Minute 1/7...
  ...
  Minute 6/7...
    Current state: ALARM
  ✓ Alarm triggered after 6 minutes

Final alarm state: ALARM
✓ Phase 2 complete: Alarm triggered successfully

Phase 3: Resuming pings to resolve alarm...
------------------------------------------------------------
  ✓ Sent ping 1
  ...
  ✓ Sent ping 12

Sent 12 pings over 6 minutes
Waiting for alarm to resolve...
  Checking... (1/3)
    Current state: OK
  ✓ Alarm resolved after 1 minute(s)

Final alarm state: OK
✓ Phase 3 complete: Alarm resolved successfully

========================================
Alarm Behavior Test Summary
========================================
✓ Alarm triggered when pings stopped (Requirement 3.2)
✓ Alarm resolved when pings resumed (Requirement 3.3)

Alarm was in ALARM state for 7.2 minutes
========================================
```

## Troubleshooting

### Test Fails: "Stack not found"

Ensure the CDK stack is deployed:
```bash
./deploy_aws.sh
```

### Test Fails: Alarm doesn't trigger

Check alarm configuration:
```bash
aws cloudwatch describe-alarms --alarm-names <alarm-name>
```

Verify Lambda is logging:
```bash
aws logs tail /aws/lambda/<function-name> --follow
```

### Test Times Out

The test can take 15+ minutes. Ensure:
- Stable internet connection
- AWS services are responding
- Lambda function is working correctly

## Future Enhancements

Potential improvements:
1. Add test for SNS notification delivery (requires email verification)
2. Add test for alarm notification frequency (every 5 minutes)
3. Add test for multiple consecutive alarm triggers
4. Add performance metrics collection during test
5. Add test for alarm behavior with intermittent connectivity

## References

- Design Document: `.kiro/specs/aws-migration/design.md`
- Requirements Document: `.kiro/specs/aws-migration/requirements.md`
- Task List: `.kiro/specs/aws-migration/tasks.md`
