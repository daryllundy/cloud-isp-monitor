#!/bin/bash
# Test deploy_cloud.sh prerequisite checking without deploying

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_cloud.sh"

echo "=========================================="
echo "Testing deploy_cloud.sh Prerequisites"
echo "=========================================="
echo ""

if [ ! -x "$DEPLOY_SCRIPT" ]; then
    echo "Error: deploy_cloud.sh not found or not executable"
    exit 1
fi

echo "Testing Azure prerequisites..."
echo "-------------------------------------------"
"$DEPLOY_SCRIPT" --cloud=azure --check
echo ""

echo "Testing AWS prerequisites..."
echo "-------------------------------------------"
"$DEPLOY_SCRIPT" --cloud=aws --check
echo ""

echo "Testing both clouds prerequisites..."
echo "-------------------------------------------"
"$DEPLOY_SCRIPT" --cloud=both --check
echo ""

echo "=========================================="
echo "All prerequisite checks completed!"
echo "=========================================="
