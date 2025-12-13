#!/bin/bash
set -e

# Test the AWS deployment without actually deploying
# 1. Check requirements
# 2. Run CDK Synth
# 3. Verify CloudFormation template valid

echo "Running AWS Deployment Test (Dry Run)..."

# Load env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check vars
if [ -z "$AWS_REGION" ]; then
  echo "Error: AWS_REGION not set."
  exit 1
fi

cd cdk
if [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# Synth
echo "Synthesizing CDK stack..."
cdk synth --strict --quiet

echo "CDK Synth successful. Template generated in cdk.out/"
echo "Test Complete."
