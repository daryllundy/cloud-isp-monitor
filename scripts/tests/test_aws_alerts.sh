#!/bin/bash
set -e

# Validate CloudWatch Alarms and SNS Topics
# Requires AWS CLI and jq

STACK_NAME=$(cdk list --context quiet=true 2>/dev/null | head -n 1)

if [ -z "$STACK_NAME" ]; then
    echo "Error: Could not determine stack name. Is it deployed?"
    echo "Try running 'cdk list' in cdk/ directory."
    exit 1
fi

echo "Verifying Alerts for Stack: $STACK_NAME"

echo "1. Checking CloudWatch Alarms..."
alarms=$(aws cloudwatch describe-alarms --alarm-name-prefix "$STACK_NAME" --query "MetricAlarms[*].[AlarmName,StateValue,MetricName,Namespace]" --output table)
echo "$alarms"

echo "2. Checking SNS Topic..."
# Get Topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TopicArn'].OutputValue" --output text)

if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
    echo "Topic ARN: $TOPIC_ARN"
    echo "Subscriptions:"
    aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query "Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]" --output table
else
    echo "Topic ARN not found in stack outputs."
fi

echo "Done."
