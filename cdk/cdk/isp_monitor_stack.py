import os
from dataclasses import dataclass
from pathlib import Path

from aws_cdk import (
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
)
from constructs import Construct


REPO_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class StackConfig:
    prefix: str
    removal_policy: RemovalPolicy
    log_retention: logs.RetentionDays
    heartbeat_period_minutes: int = 3
    heartbeat_threshold: int = 1


def _load_stack_config() -> StackConfig:
    return StackConfig(
        prefix=os.getenv("PREFIX", "isp-monitor"),
        removal_policy=getattr(
            RemovalPolicy,
            os.getenv("CDK_REMOVAL_POLICY", "DESTROY").upper(),
            RemovalPolicy.DESTROY,
        ),
        log_retention=_resolve_log_retention(int(os.getenv("LOG_RETENTION_DAYS", "7"))),
    )


def _resolve_log_retention(retention_days: int) -> logs.RetentionDays:
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
    return retention_map.get(retention_days, logs.RetentionDays.ONE_WEEK)


def _lambda_asset_excludes() -> list[str]:
    return [
        ".git/**",
        ".history/**",
        ".hypothesis/**",
        ".pytest_cache/**",
        ".venv/**",
        ".vscode/**",
        "__pycache__/**",
        "*.pyc",
        ".DS_Store",
        "Ping/**",
        "cdk/**",
        "docs/**",
        "logs/**",
        "scripts/**",
        "tests/**",
        "lambda/**",
        ".env",
        ".env.example",
        ".funcignore",
        ".gitignore",
        "README.md",
        "host.json",
        "local.settings.json",
        "main.bicep",
        "requirements.txt",
    ]


class IspMonitorStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, alert_email: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        config = _load_stack_config()

        log_group = logs.LogGroup(
            self,
            "HeartbeatLogGroup",
            log_group_name=f"/aws/lambda/{config.prefix}-heartbeat",
            retention=config.log_retention,
            removal_policy=config.removal_policy,
        )

        heartbeat_fn = _lambda.Function(
            self,
            "HeartbeatHandler",
            function_name=f"{config.prefix}-heartbeat",
            runtime=_lambda.Runtime.PYTHON_3_11,
            architecture=_lambda.Architecture.ARM_64,
            handler="aws_handler.lambda_handler",
            code=_lambda.Code.from_asset(str(REPO_ROOT), exclude=_lambda_asset_excludes()),
            memory_size=128,
            timeout=Duration.seconds(10),
            log_group=log_group,
        )

        fn_url = heartbeat_fn.add_function_url(
            auth_type=_lambda.FunctionUrlAuthType.NONE,
            cors=_lambda.FunctionUrlCorsOptions(
                allowed_origins=["*"],
                allowed_methods=[_lambda.HttpMethod.POST, _lambda.HttpMethod.GET],
            ),
        )

        metric_filter = log_group.add_metric_filter(
            "HeartbeatMetricFilter",
            filter_pattern=logs.FilterPattern.literal("[heartbeat]"),
            metric_name="HeartbeatCount",
            metric_namespace="ISPMonitor",
            metric_value="1",
            default_value=0,
        )

        heartbeat_metric = metric_filter.metric(
            statistic="Sum",
            period=Duration.minutes(config.heartbeat_period_minutes),
        )
        alarm = heartbeat_metric.create_alarm(
            self,
            "HeartbeatAlarm",
            alarm_description="Alarm if ISP Monitor heartbeat is missing",
            evaluation_periods=1,
            threshold=config.heartbeat_threshold,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

        topic = sns.Topic(self, "AlertTopic")
        if alert_email:
            topic.add_subscription(subs.EmailSubscription(alert_email))

        alarm.add_alarm_action(cw_actions.SnsAction(topic))
        alarm.add_ok_action(cw_actions.SnsAction(topic))

        CfnOutput(self, "FunctionUrl", value=fn_url.url)
        CfnOutput(self, "TopicArn", value=topic.topic_arn)
        CfnOutput(self, "AlarmName", value=alarm.alarm_name)
        CfnOutput(self, "FunctionName", value=heartbeat_fn.function_name)
