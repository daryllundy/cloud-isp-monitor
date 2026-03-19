#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ALERT_EMAIL="${ALERT_EMAIL:-test@example.com}"
TEST_AWS_REGION="${AWS_REGION:-us-west-1}"

echo "Running AWS wrapper smoke test..."
AWS_REGION="$TEST_AWS_REGION" ALERT_EMAIL="$TEST_ALERT_EMAIL" \
    "$REPO_ROOT/scripts/deploy/deploy_aws.sh" --check

echo "AWS wrapper smoke test passed."
