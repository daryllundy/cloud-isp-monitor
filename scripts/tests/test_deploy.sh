#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ALERT_EMAIL="${ALERT_EMAIL:-test@example.com}"
TEST_RG="${RG:-isp-monitor-rg}"
TEST_LOCATION="${LOCATION:-westus2}"

echo "Running Azure wrapper smoke test..."
RG="$TEST_RG" LOCATION="$TEST_LOCATION" ALERT_EMAIL="$TEST_ALERT_EMAIL" \
    "$REPO_ROOT/scripts/deploy/deploy.sh" --check

echo "Azure wrapper smoke test passed."
