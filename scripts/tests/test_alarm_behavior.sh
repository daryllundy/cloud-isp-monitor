#!/bin/bash
# Script to run the CloudWatch Alarm behavior test
# This test takes approximately 12-15 minutes to complete

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CloudWatch Alarm Behavior Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Load .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
  echo -e "${GREEN}✓ Loaded .env configuration${NC}"
else
  echo -e "${RED}✗ .env file not found${NC}"
  echo "  Please create .env with AWS configuration"
  exit 1
fi

# Check prerequisites
echo ""
echo "Checking prerequisites..."
echo "-----------------------------------"

if [ -z "$AWS_REGION" ]; then
    echo -e "${RED}✗ AWS_REGION not set in .env${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS_REGION: $AWS_REGION${NC}"

if [ -z "$PREFIX" ]; then
    echo -e "${YELLOW}⚠ PREFIX not set, using default: IspMonitor${NC}"
    export PREFIX="IspMonitor"
fi
echo -e "${GREEN}✓ PREFIX: $PREFIX${NC}"

# Check if stack exists
STACK_NAME="${PREFIX}Stack"
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    echo -e "${RED}✗ Stack $STACK_NAME not found${NC}"
    echo "  Please deploy the stack first: ./deploy_aws.sh"
    exit 1
fi
echo -e "${GREEN}✓ Stack $STACK_NAME exists${NC}"

# Check if test dependencies are installed
if ! python3 -c "import pytest, boto3, requests" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Test dependencies not installed${NC}"
    echo "  Installing dependencies..."
    pip install -q -r tests/requirements.txt
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Test dependencies installed${NC}"
fi

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}WARNING: This test takes 12-15 minutes${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "The test will:"
echo "  1. Send heartbeat pings for 6 minutes"
echo "  2. Stop pings and wait 7 minutes for alarm"
echo "  3. Resume pings and wait 6 minutes for resolution"
echo ""
echo "This is necessary because CloudWatch alarms"
echo "evaluate metrics every 5 minutes."
echo ""

# Ask for confirmation
read -p "Continue with the test? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}Starting alarm behavior test...${NC}"
echo ""

# Enable E2E tests and run the alarm behavior test
export E2E_TEST_ENABLED=1

# Run the test with verbose output
if pytest tests/test_alarm.py::test_alarm_behavior -v -s; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Alarm Behavior Test PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "The test verified:"
    echo "  ✓ Alarm triggers when pings stop (Requirement 3.2)"
    echo "  ✓ Alarm resolves when pings resume (Requirement 3.3)"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Alarm Behavior Test FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Check the output above for details."
    echo ""
    echo "Common issues:"
    echo "  • Stack not fully deployed"
    echo "  • CloudWatch alarm misconfigured"
    echo "  • Lambda function not responding"
    echo "  • Network connectivity issues"
    echo ""
    exit 1
fi
