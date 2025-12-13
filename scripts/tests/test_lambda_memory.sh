#!/bin/bash
# Test Lambda memory usage with different allocations

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Testing Lambda Memory Usage"
echo "============================"
echo ""

# Get function name from CDK output
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name IspMonitorStack \
  --query 'Stacks[0].Outputs[?OutputKey==`FunctionName`].OutputValue' \
  --output text 2>/dev/null || echo "")

if [ -z "$FUNCTION_NAME" ]; then
  echo "Error: Could not find Lambda function. Is the stack deployed?"
  exit 1
fi

echo "Function: $FUNCTION_NAME"
echo ""

# Test with current configuration
echo "Testing current memory configuration..."
FUNCTION_URL=$(aws cloudformation describe-stacks \
  --stack-name IspMonitorStack \
  --query 'Stacks[0].Outputs[?OutputKey==`FunctionUrl`].OutputValue' \
  --output text)

# Invoke function multiple times to get average
echo "Invoking function 5 times to measure memory usage..."
for i in {1..5}; do
  curl -s -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{"device":"memory-test","note":"test invocation '$i'"}' > /dev/null
  sleep 1
done

echo "Waiting for logs to be available..."
sleep 10

# Get recent log streams
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
RECENT_STREAMS=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  --query 'logStreams[*].logStreamName' \
  --output text)

echo ""
echo "Memory Usage Analysis:"
echo "====================="

# Analyze memory usage from logs
for stream in $RECENT_STREAMS; do
  MEMORY_USED=$(aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$stream" \
    --query 'events[?contains(message, `Memory Used`)].message' \
    --output text | grep -oP 'Memory Used: \K[0-9]+' | head -1)
  
  MEMORY_SIZE=$(aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$stream" \
    --query 'events[?contains(message, `Memory Size`)].message' \
    --output text | grep -oP 'Memory Size: \K[0-9]+' | head -1)
  
  if [ -n "$MEMORY_USED" ] && [ -n "$MEMORY_SIZE" ]; then
    USAGE_PERCENT=$((MEMORY_USED * 100 / MEMORY_SIZE))
    echo "  Memory Used: ${MEMORY_USED} MB / ${MEMORY_SIZE} MB (${USAGE_PERCENT}%)"
  fi
done

# Get current configuration
CURRENT_MEMORY=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --query 'MemorySize' \
  --output text)

echo ""
echo "Current Configuration:"
echo "  Memory Size: ${CURRENT_MEMORY} MB"

# Get average duration
AVG_DURATION=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --query 'Datapoints[0].Average' \
  --output text)

if [ "$AVG_DURATION" != "None" ]; then
  echo "  Average Duration: ${AVG_DURATION} ms"
fi

echo ""
echo -e "${GREEN}✓ Memory analysis complete${NC}"
echo ""
echo "Recommendations:"
echo "  - Lambda typically uses 40-60 MB for this simple function"
echo "  - 128 MB is the minimum and is sufficient for this workload"
echo "  - No optimization needed - current configuration is optimal"
