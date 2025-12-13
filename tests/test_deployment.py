import os
import subprocess
import pytest
import boto3

@pytest.mark.integration
def test_deployment_script():
    """
    Test the deployment script.
    WARNING: This test deploys real resources to AWS and may incur costs.
    It ensures the script runs successfully and resources are created.
    """
    # SKIP if not explicitly enabled to avoid accidental deploys
    if not os.getenv("RUN_DEPLOYMENT_TEST"):
        pytest.skip("Skipping deployment test. Set RUN_DEPLOYMENT_TEST=1 to run.")

    # Run deployment script
    result = subprocess.run(["./deploy_aws.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"Deployment script failed: {result.stderr}"

    # Verify stack exists
    # Assuming standard prefix
    prefix = os.getenv("PREFIX", "IspMonitor")
    stack_name = f"{prefix}Stack"
    
    cfn = boto3.client("cloudformation")
    response = cfn.describe_stacks(StackName=stack_name)
    assert len(response["Stacks"]) == 1
    assert response["Stacks"][0]["StackStatus"] in ["CREATE_COMPLETE", "UPDATE_COMPLETE"]

    # Verify Lambda Function URL is output
    outputs = response["Stacks"][0].get("Outputs", [])
    fn_url = next((o["OutputValue"] for o in outputs if o["OutputKey"] == "FunctionUrl"), None)
    assert fn_url is not None
    assert fn_url.startswith("https://")

    # Cleanup (Optional - currently manual)
    # subprocess.run(["cdk", "destroy", "--force"], cwd="cdk", check=True)
