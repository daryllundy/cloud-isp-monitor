# Scripts Documentation

This document describes all helper scripts in the project and their usage.

## Deployment Scripts

### `deploy.sh` (Azure)

Deploys the ISP Monitor infrastructure and function code to Azure.

**Usage:**
```bash
./deploy.sh
```

**Prerequisites:**
- Azure CLI installed and authenticated (`az login`)
- `.env` file configured with required variables
- `jq` installed for JSON parsing

**What it does:**
1. Sources environment variables from `.env`
2. Creates resource group if it doesn't exist
3. Deploys Bicep template (infrastructure)
4. Packages and deploys function code
5. Tests the deployed endpoint
6. Displays configuration summary

**Environment Variables Required:**
- `RG` - Resource group name
- `LOCATION` - Azure region
- `ALERT_EMAIL` - Email for alerts
- `PREFIX` - Resource name prefix (optional, defaults to "darylhome")

---

### `deploy_aws.sh` (AWS)

Deploys the ISP Monitor infrastructure to AWS using CDK.

**Usage:**
```bash
./deploy_aws.sh
```

**Prerequisites:**
- AWS CLI installed and configured (`aws configure`)
- Node.js and npm installed (for CDK)
- Python 3.8+ installed
- `.env` file configured with AWS variables

**What it does:**
1. Sources environment variables from `.env`
2. Validates required variables
3. Installs CDK dependencies
4. Bootstraps CDK (first deployment only)
5. Synthesizes CloudFormation template
6. Deploys CDK stack
7. Tests the Lambda function URL
8. Displays configuration summary

**Environment Variables Required:**
- `AWS_REGION` - AWS region (e.g., us-east-1)
- `ALERT_EMAIL` - Email for SNS notifications
- `PREFIX` - Stack name prefix (optional, defaults to "isp-monitor")

**Optional Variables:**
- `LOG_RETENTION_DAYS` - CloudWatch log retention (default: 7)
- `LAMBDA_MEMORY_MB` - Lambda memory allocation (default: 128)

---

## Agent Management Scripts

### `start_heartbeat.sh`

Starts the heartbeat agent in a detached tmux session.

**Usage:**
```bash
./start_heartbeat.sh
```

**Prerequisites:**
- `tmux` installed (`brew install tmux` on macOS)
- `.env` file configured with heartbeat variables
- `heartbeat_agent.py` executable

**What it does:**
1. Checks if tmux session already exists
2. Creates new tmux session named "isp-monitor"
3. Starts heartbeat agent in daemon mode
4. Detaches from session (runs in background)

**Environment Variables Required:**
- `HEARTBEAT_URL` - Function endpoint URL
- `HEARTBEAT_DEVICE` - Device identifier
- `HEARTBEAT_INTERVAL` - Ping interval in seconds (default: 60)

**View agent logs:**
```bash
tmux attach -t isp-monitor  # Attach to session (Ctrl+B then D to detach)
tmux capture-pane -pt isp-monitor -S -50  # View last 50 lines
```

---

### `stop_heartbeat.sh`

Stops the heartbeat agent by killing the tmux session.

**Usage:**
```bash
./stop_heartbeat.sh
```

**What it does:**
1. Checks if tmux session exists
2. Kills the "isp-monitor" session
3. Confirms agent stopped

---

## Testing Scripts

### `test_deploy.sh` (Azure)

Validates Azure deployment without actually deploying.

**Usage:**
```bash
./test_deploy.sh
```

**What it does:**
- Validates Bicep template syntax
- Checks for deployment errors
- Performs dry-run validation

---

### `test_aws_deploy.sh` (AWS)

Validates AWS CDK deployment without deploying.

**Usage:**
```bash
./test_aws_deploy.sh
```

**What it does:**
- Synthesizes CloudFormation template
- Validates CDK stack configuration
- Checks for errors and warnings

---

### `test_alerts.sh` (Azure)

Verifies Azure Monitor alert configuration.

**Usage:**
```bash
./test_alerts.sh
```

**Prerequisites:**
- Azure infrastructure deployed
- `.env` file configured

**What it does:**
- Checks alert rule configuration
- Verifies action group settings
- Displays alert evaluation settings
- Tests alert query

---

### `test_aws_alerts.sh` (AWS)

Verifies AWS CloudWatch alarm configuration.

**Usage:**
```bash
./test_aws_alerts.sh
```

**Prerequisites:**
- AWS infrastructure deployed

**What it does:**
- Checks CloudWatch alarm configuration
- Verifies SNS subscription status
- Displays alarm evaluation settings

---

### `test_alarm_behavior.sh` (AWS)

Runs comprehensive alarm behavior test (takes 12-15 minutes).

**Usage:**
```bash
./test_alarm_behavior.sh
```

**Prerequisites:**
- AWS infrastructure deployed
- Python 3.8+ with pytest installed
- Test dependencies installed (`pip install -r tests/requirements.txt`)

**What it does:**
1. Sends initial heartbeat pings
2. Stops pings for 6+ minutes
3. Verifies alarm enters ALARM state
4. Resumes pings
5. Verifies alarm returns to OK state

**Requirements Validated:**
- Requirement 3.2: Alarm triggers when pings stop
- Requirement 3.3: Alarm auto-resolves when pings resume

---

### `test_e2e_aws.sh` (AWS)

Interactive end-to-end verification guide.

**Usage:**
```bash
./test_e2e_aws.sh
```

**What it does:**
- Guides through deployment verification
- Provides step-by-step instructions
- Helps verify all components working

---

### `run_e2e_verification.sh` (AWS)

Automated end-to-end verification script.

**Usage:**
```bash
./run_e2e_verification.sh
```

**What it does:**
- Deploys infrastructure
- Sends test heartbeats
- Verifies CloudWatch Logs
- Checks alarm configuration
- Provides verification checklist

---

### `test_lambda_memory.sh` (AWS)

Tests Lambda memory usage and performance.

**Usage:**
```bash
./test_lambda_memory.sh
```

**Prerequisites:**
- AWS infrastructure deployed

**What it does:**
1. Invokes Lambda function multiple times
2. Analyzes memory usage from CloudWatch Logs
3. Displays memory statistics
4. Provides optimization recommendations

---

## Diagnostic Scripts

### `diagnose_alerts.sh` (Azure)

Diagnoses Azure alert notification issues.

**Usage:**
```bash
./diagnose_alerts.sh
```

**What it does:**
- Checks action group configuration
- Verifies email receiver status
- Tests alert rule query
- Provides troubleshooting recommendations

---

### `security_review.sh` (AWS)

Performs comprehensive security review of AWS deployment.

**Usage:**
```bash
./security_review.sh
```

**Prerequisites:**
- AWS infrastructure deployed

**What it does:**
1. Checks IAM role permissions
2. Verifies no secrets in environment variables
3. Validates HTTPS-only configuration
4. Reviews input validation implementation
5. Checks CloudWatch Logs encryption
6. Verifies SNS topic configuration
7. Provides security recommendations

**Requirements Validated:**
- Requirement 1.5: IAM roles for authentication
- Requirement 7.2: No secrets in environment
- Requirement 9.2: HTTPS-only configuration
- Requirements 2.2-2.4: Input validation

---

## Script Permissions

All scripts should be executable. If you get "Permission denied" errors, run:

```bash
chmod +x *.sh
```

## Common Issues

### "command not found" errors

**tmux not found:**
```bash
brew install tmux  # macOS
sudo apt-get install tmux  # Ubuntu/Debian
```

**jq not found:**
```bash
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu/Debian
```

**aws not found:**
```bash
# Install AWS CLI v2
# See: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```

### ".env file not found"

Create `.env` from the example:
```bash
cp .env.example .env
# Edit .env with your configuration
```

### "Stack not deployed" errors

Deploy the infrastructure first:
```bash
./deploy_aws.sh  # For AWS
./deploy.sh      # For Azure
```

## Script Development

When creating new scripts:

1. **Add shebang**: `#!/bin/bash`
2. **Set error handling**: `set -e` (exit on error)
3. **Add description**: Comment at top explaining purpose
4. **Make executable**: `chmod +x script.sh`
5. **Document here**: Add entry to this file
6. **Test thoroughly**: Run in clean environment

## See Also

- [README.md](../README.md) - Main documentation
- [README_AWS.md](../README_AWS.md) - AWS deployment guide
- [AGENT_README.md](AGENT_README.md) - Agent documentation
- [SECURITY_REVIEW.md](SECURITY_REVIEW.md) - Security analysis
