from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_cloudwatch_actions as cw_actions,
)
from constructs import Construct
import os

class IspMonitorStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, alert_email: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get prefix from environment
        prefix = os.getenv("PREFIX", "isp-monitor")
        
        # 3.4 Create CloudWatch Log Group first with fixed name
        # We explicitly create the log group to set retention and encryption
        removal_policy = getattr(RemovalPolicy, os.getenv("CDK_REMOVAL_POLICY", "DESTROY").upper(), RemovalPolicy.DESTROY)
        
        # Configurable log retention (default: 7 days)
        retention_days = int(os.getenv("LOG_RETENTION_DAYS", "7"))
        retention_map = {
            1: logs.RetentionDays.ONE_DAY,
            3: logs.RetentionDays.THREE_DAYS,
            5: logs.RetentionDays.FIVE_DAYS,
            7: logs.RetentionDays.ONE_WEEK,
            14: logs.RetentionDays.TWO_WEEKS,
            30: logs.RetentionDays.ONE_MONTH,
            60: logs.RetentionDays.TWO_MONTHS,
            90: logs.RetentionDays.THREE_MONTHS,
            180: logs.RetentionDays.SIX_MONTHS,
            365: logs.RetentionDays.ONE_YEAR,
        }
        retention = retention_map.get(retention_days, logs.RetentionDays.ONE_WEEK)
        
        # Use fixed log group name to avoid conflicts
        log_group_name = f"/aws/lambda/{prefix}-heartbeat"
        log_group = logs.LogGroup(
            self, "HeartbeatLogGroup",
            log_group_name=log_group_name,
            retention=retention,
            removal_policy=removal_policy
        )

        # 3.2 Define Lambda function resource with fixed name
        heartbeat_fn = _lambda.Function(
            self, "HeartbeatHandler",
            function_name=f"{prefix}-heartbeat",
            runtime=_lambda.Runtime.PYTHON_3_11,
            architecture=_lambda.Architecture.ARM_64,
            handler="handler.lambda_handler",
            code=_lambda.Code.from_asset("../lambda"),
            memory_size=128,
            timeout=Duration.seconds(10),
            log_group=log_group,  # Use the pre-created log group
        )

        # 3.3 Create Lambda Function URL
        fn_url = heartbeat_fn.add_function_url(
            auth_type=_lambda.FunctionUrlAuthType.NONE,
            cors=_lambda.FunctionUrlCorsOptions(
                allowed_origins=["*"],
                allowed_methods=[_lambda.HttpMethod.POST, _lambda.HttpMethod.GET],
            )
        )

        # 3.5 Create CloudWatch Metric Filter
        # Filter for heartbeat messages (text pattern, not JSON)
        # The Lambda logs: [heartbeat] {"ts": ..., "device": ..., ...}
        metric_filter = log_group.add_metric_filter(
            "HeartbeatMetricFilter",
            filter_pattern=logs.FilterPattern.literal("[heartbeat]"),
            metric_name="HeartbeatCount",
            metric_namespace="ISPMonitor",
            metric_value="1",
            default_value=0, # Ensure data points even when no logs
        )

        # 3.6 Create CloudWatch Alarm
        # Trigger if sum of heartbeats < 1 in 3 minutes
        alarm = float_metric = metric_filter.metric(
            statistic="Sum",
            period=Duration.minutes(3)
        ).create_alarm(
            self, "HeartbeatAlarm",
            alarm_description="Alarm if ISP Monitor heartbeat is missing",
            evaluation_periods=1,
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

        # 3.7 Create SNS Topic and email subscription
        topic = sns.Topic(self, "AlertTopic")
        
        if alert_email:
            topic.add_subscription(subs.EmailSubscription(alert_email))

        # Add alarm action
        alarm.add_alarm_action(cw_actions.SnsAction(topic))
        alarm.add_ok_action(cw_actions.SnsAction(topic))

        # 3.9 Add stack outputs
        CfnOutput(self, "FunctionUrl", value=fn_url.url)
        CfnOutput(self, "TopicArn", value=topic.topic_arn)
        CfnOutput(self, "AlarmName", value=alarm.alarm_name)
        CfnOutput(self, "FunctionName", value=heartbeat_fn.function_name)
