import pytest

aws_cdk = pytest.importorskip("aws_cdk")
assertions = pytest.importorskip("aws_cdk.assertions")

from cdk.isp_monitor_stack import IspMonitorStack


def test_stack_creates_expected_lambda_resources():
    app = aws_cdk.App()
    stack = IspMonitorStack(app, "IspMonitorTestStack", alert_email="alerts@example.com")
    template = assertions.Template.from_stack(stack)

    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "Handler": "aws_handler.lambda_handler",
            "Architectures": ["arm64"],
            "Runtime": "python3.11",
            "MemorySize": 128,
            "Timeout": 10,
        },
    )
    template.resource_count_is("AWS::Lambda::Url", 1)
    template.has_resource_properties(
        "AWS::Logs::LogGroup",
        {
            "LogGroupName": "/aws/lambda/isp-monitor-heartbeat",
        },
    )


def test_stack_creates_alarm_and_notification_pipeline():
    app = aws_cdk.App()
    stack = IspMonitorStack(app, "IspMonitorTestStack", alert_email="alerts@example.com")
    template = assertions.Template.from_stack(stack)

    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {
            "Threshold": 1,
            "EvaluationPeriods": 1,
            "ComparisonOperator": "LessThanThreshold",
            "TreatMissingData": "breaching",
        },
    )
    template.resource_count_is("AWS::SNS::Topic", 1)
    template.resource_count_is("AWS::SNS::Subscription", 1)
    template.has_output("FunctionUrl", {})
    template.has_output("TopicArn", {})
    template.has_output("AlarmName", {})
    template.has_output("FunctionName", {})
