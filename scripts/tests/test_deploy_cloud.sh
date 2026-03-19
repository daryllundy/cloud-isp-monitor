#!/bin/bash
# Test deploy_cloud.sh prerequisite checking without deploying

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_SCRIPT="$REPO_ROOT/scripts/deploy/deploy_cloud.sh"

echo "=========================================="
echo "Testing deploy_cloud.sh Prerequisites"
echo "=========================================="
echo ""

if [ ! -x "$DEPLOY_SCRIPT" ]; then
    echo "Error: deploy_cloud.sh not found or not executable"
    exit 1
fi

TEST_ALERT_EMAIL="${ALERT_EMAIL:-test@example.com}"
TEST_RG="${RG:-isp-monitor-rg}"
TEST_LOCATION="${LOCATION:-westus2}"
TEST_AWS_REGION="${AWS_REGION:-us-west-1}"

echo "Testing Azure prerequisites..."
echo "-------------------------------------------"
RG="$TEST_RG" LOCATION="$TEST_LOCATION" ALERT_EMAIL="$TEST_ALERT_EMAIL" \
    "$DEPLOY_SCRIPT" --provider=azure --check
echo ""

echo "Testing AWS prerequisites..."
echo "-------------------------------------------"
AWS_REGION="$TEST_AWS_REGION" ALERT_EMAIL="$TEST_ALERT_EMAIL" \
    "$DEPLOY_SCRIPT" --provider=aws --check
echo ""

echo "Testing both providers prerequisites..."
echo "-------------------------------------------"
RG="$TEST_RG" LOCATION="$TEST_LOCATION" AWS_REGION="$TEST_AWS_REGION" ALERT_EMAIL="$TEST_ALERT_EMAIL" \
    "$DEPLOY_SCRIPT" --provider=both --check
echo ""

echo "=========================================="
echo "All prerequisite checks completed!"
echo "=========================================="
