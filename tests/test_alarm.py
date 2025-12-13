"""
Integration test for CloudWatch Alarm behavior.

This test verifies that the CloudWatch Alarm correctly detects missing heartbeats
and automatically resolves when heartbeats resume.

Requirements tested:
- 3.2: WHEN no heartbeat pings are detected within the window THEN the system SHALL trigger an alert
- 3.3: WHEN heartbeat pings resume THEN the system SHALL automatically resolve the alert
"""

import os
import time
import uuid
import pytest
import boto3
import requests
from datetime import datetime, timedelta


@pytest.mark.integration
@pytest.mark.slow
def test_alarm_behavior():
    """
    Test CloudWatch Alarm behavior: trigger on missing pings, resolve on resumed pings.
    
    This test:
    1. Sends heartbeat pings to establish OK state
    2. Stops sending pings for 6+ minutes
    3. Verifies alarm enters ALARM state
    4. Resumes sending pings
    5. Verifies alarm returns to OK state
    
    Validates: Requirements 3.2, 3.3
    
    Note: This test takes approximately 12-15 minutes to complete due to
    CloudWatch alarm evaluation periods (5 minutes each).
    """
    # Skip if not explicitly enabled (this test is slow)
    if not os.getenv("E2E_TEST_ENABLED"):
        pytest.skip("Skipping alarm behavior test. Set E2E_TEST_ENABLED=1 to run.")
    
    # Get configuration
    prefix = os.getenv("PREFIX", "IspMonitor")
    stack_name = f"{prefix}Stack"
    
    # Get AWS clients
    cfn = boto3.client("cloudformation")
    cw = boto3.client("cloudwatch")
    
    # Get stack outputs
    try:
        response = cfn.describe_stacks(StackName=stack_name)
    except Exception as e:
        pytest.fail(f"Stack {stack_name} not found: {e}")
    
    outputs = response["Stacks"][0].get("Outputs", [])
    function_url = next((o["OutputValue"] for o in outputs if o["OutputKey"] == "FunctionUrl"), None)
    alarm_name = next((o["OutputValue"] for o in outputs if o["OutputKey"] == "AlarmName"), None)
    
    assert function_url, "FunctionUrl output not found in stack"
    assert alarm_name, "AlarmName output not found in stack"
    
    device_id = f"test-alarm-{uuid.uuid4().hex[:8]}"
    
    print(f"\n{'='*60}")
    print(f"Starting Alarm Behavior Test")
    print(f"{'='*60}")
    print(f"Device ID: {device_id}")
    print(f"Function URL: {function_url}")
    print(f"Alarm Name: {alarm_name}")
    print(f"{'='*60}\n")
    
    # Phase 1: Send heartbeats to establish OK state
    print("Phase 1: Establishing OK state...")
    print("-" * 60)
    
    # Send pings every 30 seconds for 6 minutes to ensure alarm reaches OK state
    start_time = time.time()
    ping_count = 0
    
    while time.time() - start_time < 360:  # 6 minutes
        try:
            resp = requests.post(
                function_url,
                json={"device": device_id, "note": f"test ping {ping_count}"},
                timeout=10
            )
            assert resp.status_code == 200, f"Ping failed with status {resp.status_code}"
            ping_count += 1
            print(f"  ✓ Sent ping {ping_count}")
        except Exception as e:
            print(f"  ✗ Ping failed: {e}")
        
        time.sleep(30)
    
    print(f"\nSent {ping_count} pings over 6 minutes")
    
    # Wait a bit more for alarm to evaluate
    print("Waiting 60 seconds for alarm evaluation...")
    time.sleep(60)
    
    # Check alarm state - should be OK or INSUFFICIENT_DATA
    alarm_state = _get_alarm_state(cw, alarm_name)
    print(f"Current alarm state: {alarm_state}")
    
    if alarm_state not in ["OK", "INSUFFICIENT_DATA"]:
        pytest.fail(f"Alarm should be OK or INSUFFICIENT_DATA after sending pings, but is {alarm_state}")
    
    print("✓ Phase 1 complete: Alarm is in acceptable state\n")
    
    # Phase 2: Stop sending pings and wait for alarm to trigger
    print("Phase 2: Stopping pings to trigger alarm...")
    print("-" * 60)
    print("Waiting 7 minutes for alarm to trigger...")
    print("(CloudWatch evaluates every 5 minutes)")
    
    # Wait 7 minutes (5 min evaluation + 2 min buffer)
    for minute in range(1, 8):
        print(f"  Minute {minute}/7...")
        time.sleep(60)
        
        # Check alarm state after 6 minutes
        if minute >= 6:
            alarm_state = _get_alarm_state(cw, alarm_name)
            print(f"    Current state: {alarm_state}")
            
            if alarm_state == "ALARM":
                print(f"  ✓ Alarm triggered after {minute} minutes")
                break
    
    # Final check - alarm should be in ALARM state
    final_state = _get_alarm_state(cw, alarm_name)
    print(f"\nFinal alarm state: {final_state}")
    
    # Requirement 3.2: Alarm should trigger when no pings detected
    assert final_state == "ALARM", \
        f"Alarm should be in ALARM state after missing pings, but is {final_state}"
    
    print("✓ Phase 2 complete: Alarm triggered successfully\n")
    
    # Get alarm state change timestamp for verification
    alarm_history = cw.describe_alarm_history(
        AlarmName=alarm_name,
        HistoryItemType="StateUpdate",
        MaxRecords=5
    )
    
    alarm_triggered_time = None
    for item in alarm_history.get("AlarmHistoryItems", []):
        if "to ALARM" in item.get("HistorySummary", ""):
            alarm_triggered_time = item["Timestamp"]
            print(f"Alarm triggered at: {alarm_triggered_time}")
            break
    
    # Phase 3: Resume sending pings and wait for alarm to resolve
    print("\nPhase 3: Resuming pings to resolve alarm...")
    print("-" * 60)
    
    # Send pings every 30 seconds for 6 minutes
    start_time = time.time()
    ping_count = 0
    
    while time.time() - start_time < 360:  # 6 minutes
        try:
            resp = requests.post(
                function_url,
                json={"device": device_id, "note": f"resume ping {ping_count}"},
                timeout=10
            )
            assert resp.status_code == 200, f"Ping failed with status {resp.status_code}"
            ping_count += 1
            print(f"  ✓ Sent ping {ping_count}")
        except Exception as e:
            print(f"  ✗ Ping failed: {e}")
        
        time.sleep(30)
    
    print(f"\nSent {ping_count} pings over 6 minutes")
    
    # Wait for alarm to evaluate and resolve
    print("Waiting for alarm to resolve...")
    
    for minute in range(1, 4):
        print(f"  Checking... ({minute}/3)")
        time.sleep(60)
        
        alarm_state = _get_alarm_state(cw, alarm_name)
        print(f"    Current state: {alarm_state}")
        
        if alarm_state == "OK":
            print(f"  ✓ Alarm resolved after {minute} minute(s)")
            break
    
    # Final check - alarm should be back to OK state
    final_state = _get_alarm_state(cw, alarm_name)
    print(f"\nFinal alarm state: {final_state}")
    
    # Requirement 3.3: Alarm should automatically resolve when pings resume
    assert final_state == "OK", \
        f"Alarm should be in OK state after resuming pings, but is {final_state}"
    
    print("✓ Phase 3 complete: Alarm resolved successfully\n")
    
    # Get alarm resolution timestamp for verification
    alarm_history = cw.describe_alarm_history(
        AlarmName=alarm_name,
        HistoryItemType="StateUpdate",
        MaxRecords=5
    )
    
    alarm_resolved_time = None
    for item in alarm_history.get("AlarmHistoryItems", []):
        if "to OK" in item.get("HistorySummary", ""):
            alarm_resolved_time = item["Timestamp"]
            print(f"Alarm resolved at: {alarm_resolved_time}")
            break
    
    # Summary
    print(f"\n{'='*60}")
    print("Alarm Behavior Test Summary")
    print(f"{'='*60}")
    print(f"✓ Alarm triggered when pings stopped (Requirement 3.2)")
    print(f"✓ Alarm resolved when pings resumed (Requirement 3.3)")
    
    if alarm_triggered_time and alarm_resolved_time:
        duration = (alarm_resolved_time - alarm_triggered_time).total_seconds() / 60
        print(f"\nAlarm was in ALARM state for {duration:.1f} minutes")
    
    print(f"{'='*60}\n")


def _get_alarm_state(cloudwatch_client, alarm_name):
    """
    Helper function to get the current state of a CloudWatch alarm.
    
    Args:
        cloudwatch_client: boto3 CloudWatch client
        alarm_name: Name of the alarm
    
    Returns:
        str: Current alarm state (OK, ALARM, or INSUFFICIENT_DATA)
    """
    try:
        response = cloudwatch_client.describe_alarms(AlarmNames=[alarm_name])
        alarms = response.get("MetricAlarms", [])
        
        if not alarms:
            raise ValueError(f"Alarm {alarm_name} not found")
        
        return alarms[0]["StateValue"]
    except Exception as e:
        raise RuntimeError(f"Failed to get alarm state: {e}")


@pytest.mark.integration
def test_alarm_configuration():
    """
    Verify CloudWatch Alarm is configured correctly.
    
    This test checks that the alarm has the correct configuration:
    - Evaluation period is 5 minutes
    - Threshold is less than 1 heartbeat
    - Missing data is treated as breaching
    - Alarm actions are configured
    
    Validates: Requirements 3.1, 3.2
    """
    if not os.getenv("E2E_TEST_ENABLED"):
        pytest.skip("Skipping alarm configuration test. Set E2E_TEST_ENABLED=1 to run.")
    
    # Get configuration
    prefix = os.getenv("PREFIX", "IspMonitor")
    stack_name = f"{prefix}Stack"
    
    # Get AWS clients
    cfn = boto3.client("cloudformation")
    cw = boto3.client("cloudwatch")
    
    # Get alarm name from stack outputs
    try:
        response = cfn.describe_stacks(StackName=stack_name)
    except Exception as e:
        pytest.fail(f"Stack {stack_name} not found: {e}")
    
    outputs = response["Stacks"][0].get("Outputs", [])
    alarm_name = next((o["OutputValue"] for o in outputs if o["OutputKey"] == "AlarmName"), None)
    
    assert alarm_name, "AlarmName output not found in stack"
    
    # Get alarm details
    response = cw.describe_alarms(AlarmNames=[alarm_name])
    alarms = response.get("MetricAlarms", [])
    
    assert len(alarms) == 1, f"Expected 1 alarm, found {len(alarms)}"
    
    alarm = alarms[0]
    
    print(f"\nAlarm Configuration:")
    print(f"  Name: {alarm['AlarmName']}")
    print(f"  Metric: {alarm.get('MetricName', 'N/A')}")
    print(f"  Namespace: {alarm.get('Namespace', 'N/A')}")
    print(f"  Period: {alarm.get('Period', 'N/A')} seconds")
    print(f"  Evaluation Periods: {alarm.get('EvaluationPeriods', 'N/A')}")
    print(f"  Threshold: {alarm.get('Threshold', 'N/A')}")
    print(f"  Comparison: {alarm.get('ComparisonOperator', 'N/A')}")
    print(f"  Treat Missing Data: {alarm.get('TreatMissingData', 'N/A')}")
    print(f"  Actions Enabled: {alarm.get('ActionsEnabled', 'N/A')}")
    
    # Verify configuration
    # Period should be 300 seconds (5 minutes)
    assert alarm.get("Period") == 300, \
        f"Expected period of 300 seconds, got {alarm.get('Period')}"
    
    # Evaluation periods should be 1
    assert alarm.get("EvaluationPeriods") == 1, \
        f"Expected 1 evaluation period, got {alarm.get('EvaluationPeriods')}"
    
    # Threshold should be 1 (less than 1 heartbeat)
    assert alarm.get("Threshold") == 1, \
        f"Expected threshold of 1, got {alarm.get('Threshold')}"
    
    # Comparison should be LessThanThreshold
    assert alarm.get("ComparisonOperator") == "LessThanThreshold", \
        f"Expected LessThanThreshold, got {alarm.get('ComparisonOperator')}"
    
    # Missing data should be treated as breaching
    assert alarm.get("TreatMissingData") == "breaching", \
        f"Expected TreatMissingData='breaching', got {alarm.get('TreatMissingData')}"
    
    # Actions should be enabled
    assert alarm.get("ActionsEnabled") is True, \
        "Alarm actions should be enabled"
    
    # Should have alarm actions configured
    assert len(alarm.get("AlarmActions", [])) > 0, \
        "Alarm should have alarm actions configured"
    
    print("\n✓ Alarm configuration verified")
