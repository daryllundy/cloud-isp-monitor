import os
import time
import uuid
import pytest
import boto3
import requests
from datetime import datetime, timedelta

@pytest.mark.integration
def test_e2e_heartbeat_flow():
    """
    End-to-end test for ISP Monitor.
    Requires the stack to be deployed.
    Set E2E_TEST_ENABLED=1 to run.
    """
    if not os.getenv("E2E_TEST_ENABLED"):
        pytest.skip("Skipping E2E test. Set E2E_TEST_ENABLED=1 to run.")

    # Get Stack Outputs
    prefix = os.getenv("PREFIX", "IspMonitor")
    stack_name = f"{prefix}Stack"
    cfn = boto3.client("cloudformation")
    
    try:
        response = cfn.describe_stacks(StackName=stack_name)
    except Exception as e:
        pytest.fail(f"Stack {stack_name} not found: {e}")

    outputs = response["Stacks"][0].get("Outputs", [])
    function_url = next((o["OutputValue"] for o in outputs if o["OutputKey"] == "FunctionUrl"), None)
    log_group_name = f"/aws/lambda/{next((o['OutputValue'] for o in outputs if o['OutputKey'] == 'FunctionName'), '')}"
    
    assert function_url, "FunctionUrl output not found"
    assert log_group_name, "FunctionName output not found"

    # 1. Send Heartbeat
    device_id = f"test-device-{uuid.uuid4().hex[:8]}"
    note = "E2E Test Ping"
    
    print(f"Sending ping to {function_url}...")
    resp = requests.post(function_url, json={"device": device_id, "note": note})
    assert resp.status_code == 200
    assert resp.text == "ok"

    # 2. Verify Logs (wait a bit for ingestion)
    print("Waiting for logs...")
    time.sleep(10)
    
    logs_client = boto3.client("logs")
    # Search for log entry
    query = f'fields @timestamp, @message | filter device = "{device_id}"'
    start_query_resp = logs_client.start_query(
        logGroupName=log_group_name,
        startTime=int((datetime.now() - timedelta(minutes=5)).timestamp()),
        endTime=int(datetime.now().timestamp()),
        queryString=query
    )
    query_id = start_query_resp['queryId']
    
    # Poll for results
    for _ in range(10):
        query_results = logs_client.get_query_results(queryId=query_id)
        if query_results['status'] == 'Complete':
            results = query_results['results']
            if results:
                break
        time.sleep(2)
    
    assert len(results) >= 1, "Log entry not found in CloudWatch Logs"
    print("Log entry verified.")

    # 3. Verify Metric (Optional/Complex due to delay)
    # We won't test alarm triggering as it takes 5+ minutes, but we can check metric existence
    
    print("E2E Test passed!")
