# Migration Guide: Azure to AWS

This guide outlines the steps to migrate your ISP Monitor from Azure to AWS.

## differences

| Feature | Azure | AWS |
| :--- | :--- | :--- |
| **Compute** | Azure Functions (Consumption) | AWS Lambda (ARM64) |
| **Endpoint** | HTTP Trigger | Lambda Function URL |
| **Monitoring** | Application Insights | CloudWatch Logs & Metrics |
| **Alerting** | Azure Monitor Alerts | CloudWatch Alarms |
| **Notifications** | Action Groups (Email) | SNS Topic (Email) |
| **Cost** | Minimal (Free Grant) | Minimal (Free Tier) |

## Migration Steps

### 1. Pre-Migration Checklist
- [ ] Ensure you have the `HEARTBEAT_URL` and `HEARTBEAT_DEVICE` from your current agent configuration.
- [ ] Verify you have access to an AWS Account.
- [ ] Install AWS CLI and CDK (`npm install -g aws-cdk`).

### 2. Deploy AWS Infrastructure
Follow the instructions in [README_AWS.md](../README_AWS.md) to deploy the new stack.
1. Configure `.env` with your email and region.
2. Run `./deploy_aws.sh`.
3. **Capture the new Function URL** from the output.

### 3. Update the Agent
On your monitoring device (e.g., Raspberry Pi):

1.  **Stop the running agent**:
    ```bash
    ./stop_heartbeat.sh
    ```

2.  **Update the URL**:
    Edit your environment variables (e.g., in `.bashrc`, `/etc/environment`, or your systemd service file) to point to the new AWS Lambda URL.
    ```bash
    # Old
    # export HEARTBEAT_URL="https://azure-func.../api/ping"
    
    # New
    export HEARTBEAT_URL="https://<lambda-id>.lambda-url.<region>.on.aws/"
    ```

3.  **Start the agent**:
    ```bash
    ./start_heartbeat.sh
    ```

### 4. Verify AWS Monitoring
1.  Check the AWS CloudWatch Console > Log Groups. You should see incoming heartbeats.
2.  Wait 5 minutes to ensure the Alarm remains in OK state.

### 5. Decommission Azure Resources
Once AWS is confirmed working:
1.  Log in to Azure Portal or use Azure CLI.
2.  Delete the Resource Group containing the Function App and Application Insights to stop all billing.
    ```bash
    az group delete --name <ResourceGroupName>
    ```
