<div align="center">

# 🌐 Cloud ISP Monitor

**Never Miss Another Internet Outage — Get Instant Alerts, Multi-Cloud Ready**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Azure Functions](https://img.shields.io/badge/Azure-Functions-0078D4?logo=microsoftazure)](https://azure.microsoft.com/services/functions/)
[![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?logo=amazonaws)](https://aws.amazon.com/lambda/)
[![Made with ❤️](https://img.shields.io/badge/Made%20with-❤️-red.svg)](https://github.com/daryllundy/cloud-isp-monitor)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

*A serverless, multi-cloud ISP monitoring solution that actually works.*

[Features](#-features) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Architecture](#-architecture)

</div>

---

## 🎯 What is This?

Ever had your internet go down and not realize it until you try to load a webpage? Or worse, your home server goes offline and you don't find out until hours later?

**Cloud ISP Monitor** is a dead-simple, serverless monitoring system that sends you email alerts the moment your internet connection drops. No complex setup, no expensive monitoring services, just a lightweight Python agent and your choice of Azure or AWS.

### 💡 Why This Exists

- 🏠 **Home Labs & Servers**: Know instantly when your self-hosted services go offline
- 🔌 **ISP Accountability**: Track outages and have data for your ISP support calls
- 📊 **Multi-Location Monitoring**: Deploy agents across multiple locations, all reporting to one dashboard
- 💰 **Ridiculously Cheap**: $0-10/month with cloud free tiers
- 🚀 **Learn Serverless**: Perfect starter project for Azure Functions or AWS Lambda

## ✨ Features

<table>
<tr>
<td width="50%">

### Cloud Native
- ☁️ **Multi-Cloud Support** — Azure or AWS (or both!)
- 🔧 **Infrastructure as Code** — Bicep for Azure, CDK for AWS
- 📦 **Serverless** — Pay only for what you use
- 🔐 **Secure by Default** — Managed identities, IAM roles

</td>
<td width="50%">

### DevOps Ready
- 🎯 **Zero Dependencies** — Agent uses stdlib only
- 🔄 **Auto-Healing** — Survives network hiccups
- 📧 **Smart Alerts** — Email on failure + recovery
- 🐛 **Battle-Tested** — Production-ready code

</td>
</tr>
</table>

## 🚀 Quick Start

Get up and running in under 5 minutes:

### 1️⃣ Clone & Configure

```bash
git clone https://github.com/daryllundy/cloud-isp-monitor.git
cd cloud-isp-monitor

# Copy example config
cp .env.example .env

# Edit with your details
nano .env
```

### 2️⃣ Deploy to Cloud

**Option A: Unified Multi-Cloud Deployment** (Recommended)

```bash
# Deploy to Azure
./scripts/deploy/deploy_cloud.sh --cloud=azure

# Or deploy to AWS
./scripts/deploy/deploy_cloud.sh --cloud=aws

# Or deploy to BOTH!
./scripts/deploy/deploy_cloud.sh --cloud=both
```

**Option B: Individual Cloud Scripts**

```bash
# Azure
./scripts/deploy/deploy.sh

# AWS
./scripts/deploy/deploy_aws.sh
```

### 3️⃣ Start Monitoring

```bash
# Make scripts executable
chmod +x heartbeat_agent.py scripts/start_heartbeat.sh scripts/stop_heartbeat.sh

# Start the agent (runs in background via tmux)
./scripts/start_heartbeat.sh

# Check it's running
tmux ls

# View live logs (Ctrl+B then D to detach)
tmux attach -t isp-monitor
```

### 4️⃣ Test It Works

```bash
# Stop the agent to trigger an alert
./scripts/stop_heartbeat.sh

# Wait 6-7 minutes, check your email
# You should receive an alert from Azure Monitor or AWS SNS

# Restart the agent
./scripts/start_heartbeat.sh

# Wait 6-7 minutes, receive recovery email
```

**That's it!** 🎉 You're now monitoring your internet connection.

## 🏗️ Architecture

### Azure Implementation

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Your Device    │         │  Azure Function  │         │ Azure Monitor   │
│  (Home/Office)  │  POST   │  /api/ping       │  Logs   │ Alert Rule      │
│                 │────────▶│  (Python 3.11)   │────────▶│ (5min window)   │
│  heartbeat_     │         │                  │         │                 │
│  agent.py       │   60s   └──────────────────┘         └─────────────────┘
│  (Cron)         │◀────┐            │                            │
└─────────────────┘     │            ▼                            ▼
                        │   ┌─────────────────┐         ┌─────────────────┐
                        └───│ App Insights    │         │ Action Group    │
                            │ (Logs/Metrics)  │         │ (Email Alert)   │
                            └─────────────────┘         └─────────────────┘
```

### AWS Implementation

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Your Device    │         │  AWS Lambda      │         │ CloudWatch      │
│  (Home/Office)  │  POST   │  /api/ping       │  Logs   │ Alarm           │
│                 │────────▶│  (Python 3.11)   │────────▶│ (5min window)   │
│  heartbeat_     │         │                  │         │                 │
│  agent.py       │   60s   └──────────────────┘         └─────────────────┘
│  (Cron)         │◀────┐            │                            │
└─────────────────┘     │            ▼                            ▼
                        │   ┌─────────────────┐         ┌─────────────────┐
                        └───│ CloudWatch Logs │         │ SNS Topic       │
                            │ (Logs/Metrics)  │         │ (Email Alert)   │
                            └─────────────────┘         └─────────────────┘
```

## 🎨 Cloud Platform Comparison

Choose your weapon:

| Feature | 🔷 Azure | 🟠 AWS |
|---------|----------|--------|
| **Serverless Function** | Azure Functions | AWS Lambda |
| **Logging** | Application Insights | CloudWatch Logs |
| **Monitoring** | Azure Monitor Alerts | CloudWatch Alarms |
| **Notifications** | Action Groups | SNS Topics |
| **IaC Tool** | Bicep | AWS CDK (Python) |
| **Authentication** | Managed Identity | IAM Roles |
| **Estimated Cost** | $2-10/month | $0-0.50/month |
| **Free Tier** | 1M executions | 1M executions |
| **Setup Complexity** | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Portal UX** | ⭐⭐⭐⭐ | ⭐⭐⭐ |

**TL;DR:**
- 🔷 Choose **Azure** if you want a great portal UX and are okay with slightly higher costs
- 🟠 Choose **AWS** if you want rock-bottom pricing and don't mind more CLI work
- 🌈 Choose **Both** if you're a DevOps engineer who lives dangerously

## 📊 Cost Breakdown

### Azure (Monthly)
- ✅ Function App (Consumption): **$0-5** (1M executions free)
- ✅ Storage Account: **~$0.50**
- ✅ Application Insights: **$2-5** (5GB free)
- 💰 **Total: $2-10/month**

### AWS (Monthly)
- ✅ Lambda: **$0** (1M requests free tier)
- ✅ CloudWatch Logs: **$0** (5GB free tier)
- ✅ CloudWatch Alarms: **$0.10** (first 10 alarms free)
- ✅ SNS: **$0** (1000 email notifications free)
- 💰 **Total: $0-0.50/month**

## 🛠️ Tech Stack

**Backend:**
- Python 3.11+ (stdlib only, zero external dependencies)
- Azure Functions / AWS Lambda
- Application Insights / CloudWatch

**Infrastructure:**
- Azure Bicep / AWS CDK
- Azure CLI / AWS CLI
- tmux (for background agent)

**Monitoring:**
- Azure Monitor / CloudWatch Alarms
- Action Groups / SNS Topics
- Log Analytics / CloudWatch Logs Insights

## 📁 Project Structure

```
.
├── 📜 README.md                    # You are here!
├── 🔧 .env.example                 # Configuration template
│
├── ☁️  Azure Stack
│   ├── main.bicep                  # Azure infrastructure (Bicep)
│   ├── Ping/                       # Azure Function code
│   │   ├── __init__.py
│   │   └── function.json
│   └── host.json
│
├── ☁️  AWS Stack
│   ├── cdk/                        # AWS infrastructure (CDK)
│   │   └── app.py
│   └── lambda/                     # Lambda function code
│       └── index.py
│
├── 🤖 Agent
│   ├── heartbeat_agent.py          # Monitoring agent (runs on your device)
│   └── scripts/
│       ├── start_heartbeat.sh      # Start agent in tmux
│       └── stop_heartbeat.sh       # Stop agent
│
├── 🚀 Deployment
│   └── scripts/deploy/
│       ├── deploy_cloud.sh         # Unified multi-cloud deployment
│       ├── deploy.sh               # Azure deployment
│       └── deploy_aws.sh           # AWS deployment
│
├── 🧪 Testing
│   └── scripts/tests/              # Test scripts
│       ├── test_e2e_aws.sh
│       └── test_alerts.sh
│
└── 📚 Documentation
    └── docs/
        ├── PLATFORM_COMPARISON.md  # Detailed Azure vs AWS comparison
        ├── MIGRATION_GUIDE.md      # Migration instructions
        ├── AGENT_README.md         # Agent documentation
        ├── SCRIPTS.md              # All scripts documentation
        └── TROUBLESHOOTING_SUMMARY.md
```

## ⚙️ Configuration

### Environment Variables (.env)

```bash
# ═══════════════════════════════════════
# AZURE CONFIGURATION
# ═══════════════════════════════════════
RG=your-project-rg
LOCATION=westus2
ALERT_EMAIL=your-email@example.com

# ═══════════════════════════════════════
# AWS CONFIGURATION
# ═══════════════════════════════════════
AWS_REGION=us-west-2
AWS_ALERT_EMAIL=your-email@example.com
CDK_STACK_NAME=IspMonitorStack

# ═══════════════════════════════════════
# HEARTBEAT AGENT CONFIGURATION
# ═══════════════════════════════════════
HEARTBEAT_URL=https://your-func.azurewebsites.net/api/ping
HEARTBEAT_DEVICE=my-home-server
HEARTBEAT_INTERVAL=60  # seconds
```

## 📡 API Endpoint

### `POST /api/ping`

**Request:**
```bash
curl -X POST https://your-func.azurewebsites.net/api/ping \
  -H "Content-Type: application/json" \
  -d '{
    "device": "home-server",
    "note": "all systems nominal"
  }'
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2025-12-12T20:00:00Z"
}
```

**Optional Headers:**
- `X-Device`: Device identifier
- `X-Forwarded-For`: Client IP (auto-captured)

## 🧪 Local Development

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Azure Functions
func start

# AWS Lambda (via SAM)
sam local start-api

# Test locally
curl http://localhost:7071/api/ping
```

## 🔍 Monitoring & Debugging

### View Logs (Azure)

```bash
# Tail function logs
az webapp log tail --name $FUNC_APP_NAME --resource-group $RG

# Query Application Insights
az monitor app-insights query \
  --app darylhome-appi \
  --resource-group $RG \
  --analytics-query "requests | where timestamp > ago(1h)"
```

### View Logs (AWS)

```bash
# Tail Lambda logs
aws logs tail /aws/lambda/IspMonitor-PingFunction --follow

# Get recent invocations
aws lambda get-function --function-name IspMonitor-PingFunction
```

### Check Alert Status

```bash
# Azure
az monitor scheduled-query list --resource-group $RG --output table

# AWS
aws cloudwatch describe-alarms --alarm-names IspMonitor-MissingPings
```

## 🐛 Troubleshooting

<details>
<summary><b>🔴 Agent SSL Certificate Errors (macOS)</b></summary>

**Error:** `[SSL: CERTIFICATE_VERIFY_FAILED]`

**Fix:**
```bash
# Find your Python version
python3 --version  # e.g., Python 3.12.0

# Install certificates (replace 3.12 with your version)
/Applications/Python\ 3.12/Install\ Certificates.command

# Alternative: Use Homebrew Python
brew install python3
```
</details>

<details>
<summary><b>📧 Not Receiving Alert Emails</b></summary>

1. **Check spam folder** for emails from:
   - Azure: `azure-noreply@microsoft.com`
   - AWS: `no-reply@sns.amazonaws.com`

2. **Confirm email address:**
   ```bash
   # Azure
   az monitor action-group show --name darylhome-ag --resource-group $RG

   # AWS
   aws sns list-subscriptions
   ```

3. **Confirm subscription** (AWS only):
   - Check your email for "AWS Notification - Subscription Confirmation"
   - Click the confirmation link

4. **Add to safe senders list** to prevent future filtering
</details>

<details>
<summary><b>🔧 Function Returns 503 Error</b></summary>

**Azure:**
```bash
# Verify Linux runtime
az functionapp show --name $FUNC_APP_NAME --resource-group $RG \
  --query "{os:kind, runtime:linuxFxVersion}"

# Should show: kind=functionapp,linux, runtime=Python|3.11

# Restart if needed
az functionapp restart --name $FUNC_APP_NAME --resource-group $RG
```

**AWS:**
```bash
# Check function configuration
aws lambda get-function-configuration --function-name IspMonitor-PingFunction

# Update runtime if needed
aws lambda update-function-configuration \
  --function-name IspMonitor-PingFunction \
  --runtime python3.11
```
</details>

<details>
<summary><b>🔄 Agent Not Sending Pings</b></summary>

```bash
# Check if tmux session exists
tmux ls

# View agent logs
tmux capture-pane -pt isp-monitor -S -50

# Kill and restart
tmux kill-session -t isp-monitor
./scripts/start_heartbeat.sh

# Test connection manually
python3 heartbeat_agent.py \
  --url https://your-func.azurewebsites.net/api/ping \
  --device test \
  --interval 60 \
  --verbose
```
</details>

## 📚 Documentation

### 📖 Guides
- [AWS Deployment Guide](docs/README_AWS.md) — Full AWS setup instructions
- [Migration Guide](docs/MIGRATION_GUIDE.md) — Azure ➡️ AWS migration
- [Platform Comparison](docs/PLATFORM_COMPARISON.md) — Detailed Azure vs AWS analysis
- [Agent Documentation](docs/AGENT_README.md) — Heartbeat agent deep-dive

### 🔧 Operations
- [Scripts Reference](docs/SCRIPTS.md) — All helper scripts explained
- [Alert Troubleshooting](docs/ALERT_TROUBLESHOOTING.md) — Alert debugging guide
- [Security Review](docs/SECURITY_REVIEW.md) — AWS security analysis
- [Security (Azure)](docs/SECURITY.md) — Azure security best practices

### 🧪 Testing
- [Test Documentation](tests/README.md) — Testing guide
- [Alarm Test Results](tests/ALARM_TEST_SUMMARY.md) — Test output examples

## 🎓 Learning Resources

**Serverless & Cloud:**
- [Azure Functions Python Guide](https://docs.microsoft.com/azure/azure-functions/functions-reference-python)
- [AWS Lambda Python Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [Serverless Framework Best Practices](https://www.serverless.com/blog/serverless-best-practices)

**Infrastructure as Code:**
- [Azure Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/v2/guide/home.html)

**Monitoring:**
- [Azure Monitor Alert Rules](https://docs.microsoft.com/azure/azure-monitor/alerts/alerts-overview)
- [CloudWatch Alarms Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)

## 🤝 Contributing

Contributions are welcome! Whether it's:

- 🐛 Bug fixes
- ✨ New features (GCP support anyone?)
- 📝 Documentation improvements
- 🧪 More tests
- 💡 Ideas and suggestions

**Please:**
1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🌟 Star History

If this project helped you, consider giving it a star! ⭐

[![Star History Chart](https://api.star-history.com/svg?repos=daryllundy/cloud-isp-monitor&type=Date)](https://star-history.com/#daryllundy/cloud-isp-monitor&Date)

## 💬 Support & Community

- 🐛 **Found a bug?** [Open an issue](https://github.com/daryllundy/cloud-isp-monitor/issues)
- 💡 **Have an idea?** [Start a discussion](https://github.com/daryllundy/cloud-isp-monitor/discussions)
- 📧 **Need help?** Check the [troubleshooting guide](docs/TROUBLESHOOTING_SUMMARY.md) first

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**TL;DR:** Do whatever you want with it, just don't sue me if your ISP still sucks. 😄

---

<div align="center">

**Made with ❤️ by developers, for developers**

*Because we all deserve to know when our internet is down* 🌐

[⭐ Star this repo](https://github.com/daryllundy/cloud-isp-monitor) • [🍴 Fork it](https://github.com/daryllundy/cloud-isp-monitor/fork) • [📖 Read the docs](docs/)

</div>
