# CI/CD Integration Guide

This guide explains how to integrate the ISP Monitor deployment scripts into your CI/CD pipelines.

## Table of Contents

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [Azure DevOps](#azure-devops)
- [General Principles](#general-principles)

## GitHub Actions

### Azure Deployment

```yaml
name: Deploy ISP Monitor to Azure

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy-azure:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Setup Environment
        run: |
          echo "RG=${{ secrets.AZURE_RG }}" >> .env
          echo "LOCATION=${{ secrets.AZURE_LOCATION }}" >> .env
          echo "ALERT_EMAIL=${{ secrets.ALERT_EMAIL }}" >> .env

      - name: Deploy to Azure
        run: |
          chmod +x deploy_cloud.sh
          ./deploy_cloud.sh --cloud=azure
```

**Required Secrets:**
- `AZURE_CREDENTIALS` - Service principal credentials (JSON format)
- `AZURE_RG` - Resource group name
- `AZURE_LOCATION` - Azure region (e.g., westus2)
- `ALERT_EMAIL` - Email for alerts

**Creating Azure Service Principal:**
```bash
az ad sp create-for-rbac \
  --name "github-isp-monitor" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/{resource-group} \
  --sdk-auth
```

---

### AWS Deployment

```yaml
name: Deploy ISP Monitor to AWS

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy-aws:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Setup Environment
        run: |
          echo "AWS_REGION=${{ secrets.AWS_REGION }}" >> .env
          echo "ALERT_EMAIL=${{ secrets.ALERT_EMAIL }}" >> .env
          echo "PREFIX=${{ secrets.AWS_PREFIX }}" >> .env

      - name: Deploy to AWS
        run: |
          chmod +x deploy_cloud.sh
          ./deploy_cloud.sh --cloud=aws
```

**Required Secrets:**
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key
- `AWS_REGION` - AWS region (e.g., us-east-1)
- `ALERT_EMAIL` - Email for SNS notifications
- `AWS_PREFIX` - Stack name prefix (e.g., isp-monitor)

---

### Multi-Cloud Deployment

```yaml
name: Deploy ISP Monitor to Multiple Clouds

on:
  workflow_dispatch:
    inputs:
      cloud:
        description: 'Target cloud (azure, aws, both)'
        required: true
        type: choice
        options:
          - azure
          - aws
          - both

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Azure Login
        if: github.event.inputs.cloud == 'azure' || github.event.inputs.cloud == 'both'
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Configure AWS Credentials
        if: github.event.inputs.cloud == 'aws' || github.event.inputs.cloud == 'both'
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Setup Node.js
        if: github.event.inputs.cloud == 'aws' || github.event.inputs.cloud == 'both'
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Setup Environment
        run: |
          # Azure variables
          echo "RG=${{ secrets.AZURE_RG }}" >> .env
          echo "LOCATION=${{ secrets.AZURE_LOCATION }}" >> .env

          # AWS variables
          echo "AWS_REGION=${{ secrets.AWS_REGION }}" >> .env
          echo "PREFIX=${{ secrets.AWS_PREFIX }}" >> .env

          # Common variables
          echo "ALERT_EMAIL=${{ secrets.ALERT_EMAIL }}" >> .env

      - name: Deploy
        run: |
          chmod +x deploy_cloud.sh
          ./deploy_cloud.sh --cloud=${{ github.event.inputs.cloud }}
```

---

## GitLab CI

### Azure Deployment

```yaml
deploy-azure:
  image: mcr.microsoft.com/azure-cli:latest
  stage: deploy
  only:
    - main
  before_script:
    - az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID
    - apk add --no-cache jq zip bash
  script:
    - echo "RG=${AZURE_RG}" >> .env
    - echo "LOCATION=${AZURE_LOCATION}" >> .env
    - echo "ALERT_EMAIL=${ALERT_EMAIL}" >> .env
    - chmod +x deploy_cloud.sh
    - ./deploy_cloud.sh --cloud=azure
  variables:
    AZURE_RG: "isp-monitor-rg"
    AZURE_LOCATION: "westus2"
```

**Required Variables (GitLab CI/CD Settings):**
- `AZURE_CLIENT_ID` - Service principal client ID
- `AZURE_CLIENT_SECRET` - Service principal secret
- `AZURE_TENANT_ID` - Azure tenant ID
- `ALERT_EMAIL` - Email for alerts

---

### AWS Deployment

```yaml
deploy-aws:
  image: amazon/aws-cli:latest
  stage: deploy
  only:
    - main
  before_script:
    - yum install -y nodejs python3 python3-pip jq
    - npm install -g aws-cdk
  script:
    - echo "AWS_REGION=${AWS_REGION}" >> .env
    - echo "ALERT_EMAIL=${ALERT_EMAIL}" >> .env
    - echo "PREFIX=${AWS_PREFIX}" >> .env
    - chmod +x deploy_cloud.sh
    - ./deploy_cloud.sh --cloud=aws
  variables:
    AWS_REGION: "us-east-1"
    AWS_PREFIX: "isp-monitor"
```

**Required Variables (GitLab CI/CD Settings):**
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key (masked)
- `AWS_REGION` - AWS region
- `ALERT_EMAIL` - Email for SNS notifications

---

## Azure DevOps

### Azure Deployment

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Deploy to Azure'
  inputs:
    azureSubscription: 'Azure Service Connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      echo "RG=$(AZURE_RG)" >> .env
      echo "LOCATION=$(AZURE_LOCATION)" >> .env
      echo "ALERT_EMAIL=$(ALERT_EMAIL)" >> .env
      chmod +x deploy_cloud.sh
      ./deploy_cloud.sh --cloud=azure
```

**Pipeline Variables:**
- `AZURE_RG` - Resource group name
- `AZURE_LOCATION` - Azure region
- `ALERT_EMAIL` - Email for alerts

---

### AWS Deployment

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseNode@1
  inputs:
    version: '18.x'

- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.11'

- script: |
    npm install -g aws-cdk
  displayName: 'Install AWS CDK'

- task: AWSShellScript@1
  displayName: 'Deploy to AWS'
  inputs:
    awsCredentials: 'AWS Service Connection'
    regionName: '$(AWS_REGION)'
    scriptType: 'inline'
    inlineScript: |
      echo "AWS_REGION=$(AWS_REGION)" >> .env
      echo "ALERT_EMAIL=$(ALERT_EMAIL)" >> .env
      echo "PREFIX=$(AWS_PREFIX)" >> .env
      chmod +x deploy_cloud.sh
      ./deploy_cloud.sh --cloud=aws
```

**Pipeline Variables:**
- `AWS_REGION` - AWS region
- `ALERT_EMAIL` - Email for SNS notifications
- `AWS_PREFIX` - Stack name prefix

---

## General Principles

### Environment Variables

Always use CI/CD secrets for sensitive information:

- **Never commit** `.env` files to version control
- **Use secret management** in your CI/CD platform
- **Validate variables** before deployment
- **Use separate environments** for dev, staging, production

### Prerequisites

Ensure CI/CD runners have required tools:

**For Azure:**
- Azure CLI
- jq (JSON processor)
- zip

**For AWS:**
- AWS CLI
- Node.js and npm (for CDK)
- Python 3.8+
- jq (JSON processor)

### Best Practices

1. **Run prerequisite checks:**
   ```bash
   ./deploy_cloud.sh --cloud=azure --check
   ```

2. **Use specific tool versions:**
   ```yaml
   - uses: actions/setup-node@v3
     with:
       node-version: '18'
   ```

3. **Cache dependencies:**
   ```yaml
   - name: Cache CDK dependencies
     uses: actions/cache@v3
     with:
       path: cdk/.venv
       key: ${{ runner.os }}-cdk-${{ hashFiles('cdk/requirements.txt') }}
   ```

4. **Separate deployment stages:**
   - Validate prerequisites
   - Deploy infrastructure
   - Run integration tests
   - Notify on success/failure

5. **Use manual approval for production:**
   ```yaml
   deploy-production:
     environment: production
     needs: deploy-staging
   ```

### Testing in CI/CD

Add a test stage before deployment:

```yaml
- name: Test Deployment Script
  run: |
    chmod +x test_deploy_cloud.sh
    ./test_deploy_cloud.sh
```

### Notifications

Add notifications for deployment status:

```yaml
- name: Notify on Success
  if: success()
  run: |
    echo "Deployment successful!"
    # Add Slack/Teams/Email notification

- name: Notify on Failure
  if: failure()
  run: |
    echo "Deployment failed!"
    # Add Slack/Teams/Email notification
```

---

## Troubleshooting

### Common Issues

1. **Authentication Failures:**
   - Verify service principal/IAM credentials
   - Check credential expiration
   - Ensure correct permissions

2. **Missing Dependencies:**
   - Install all prerequisites in CI/CD environment
   - Use appropriate base images
   - Cache dependencies when possible

3. **Environment Variable Issues:**
   - Verify all required variables are set
   - Check variable naming (case-sensitive)
   - Ensure proper secret configuration

4. **Network/Timeout Issues:**
   - Increase timeout limits
   - Check firewall rules
   - Verify cloud provider connectivity

### Debug Mode

Enable verbose logging:

```bash
set -x
./deploy_cloud.sh --cloud=azure
```

---

## Security Considerations

1. **Never log sensitive information:**
   ```yaml
   - name: Deploy
     run: ./deploy_cloud.sh --cloud=azure
     env:
       ALERT_EMAIL: ${{ secrets.ALERT_EMAIL }}
     # Don't echo secrets!
   ```

2. **Use least-privilege credentials:**
   - Azure: Contributor role on specific resource group
   - AWS: IAM role with minimal required permissions

3. **Rotate credentials regularly:**
   - Service principals
   - Access keys
   - Secrets

4. **Enable audit logging:**
   - Track all deployments
   - Monitor for unauthorized changes
   - Review logs regularly

---

## Example: Complete Production Workflow

```yaml
name: ISP Monitor Production Deployment

on:
  push:
    tags:
      - 'v*'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Validate configuration
        run: |
          chmod +x deploy_cloud.sh
          ./deploy_cloud.sh --cloud=both --check

  deploy-staging:
    needs: validate
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to staging
        run: ./deploy_cloud.sh --cloud=azure
        # Use staging credentials

  integration-test:
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - name: Run integration tests
        run: |
          # Test heartbeat endpoint
          # Verify alerts
          # Check monitoring

  deploy-production:
    needs: integration-test
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to production
        run: ./deploy_cloud.sh --cloud=both
        # Use production credentials

      - name: Verify deployment
        run: |
          # Health checks
          # Smoke tests

      - name: Notify success
        if: success()
        run: echo "Production deployment successful!"
```

---

For more information, see:
- [Main README](../README.md)
- [Scripts Documentation](SCRIPTS.md)
- [Platform Comparison](PLATFORM_COMPARISON.md)
