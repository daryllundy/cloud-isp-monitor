#!/usr/bin/env python3
import os
import aws_cdk as cdk
from cdk.isp_monitor_stack import IspMonitorStack
from dotenv import load_dotenv

# Load env from .env file if present (useful for local synthesis)
load_dotenv()

app = cdk.App()

alert_email = os.getenv('ALERT_EMAIL')
prefix = os.getenv('PREFIX', 'IspMonitor')
aws_region = os.getenv('AWS_REGION', os.getenv('CDK_DEFAULT_REGION'))
aws_account = os.getenv('AWS_ACCOUNT', os.getenv('CDK_DEFAULT_ACCOUNT'))

env = cdk.Environment(account=aws_account, region=aws_region)

IspMonitorStack(app, f"{prefix}Stack",
    env=env,
    alert_email=alert_email,
)

app.synth()
