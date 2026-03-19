# Developer Workflow

This guide is the source of truth for local development, testing, and deployment.

## Local Setup

Install the base project dependencies:

```bash
python3 -m pip install -r requirements.txt
python3 -m pip install -r tests/requirements.txt
python3 -m pip install -r cdk/requirements.txt
python3 -m pip install -r cdk/requirements-dev.txt
```

Create your local config:

```bash
cp .env.example .env
```

## Test Commands

Run the fast repo-root suite:

```bash
pytest -q
```

Run integration tests only when infrastructure is already deployed:

```bash
E2E_TEST_ENABLED=1 pytest tests -m integration
```

Run the slow alarm verification explicitly:

```bash
E2E_TEST_ENABLED=1 pytest tests/test_alarm.py::test_alarm_behavior -v -s
```

## Deploy Commands

Validate prerequisites:

```bash
./scripts/deploy/deploy_cloud.sh --provider=azure --check
./scripts/deploy/deploy_cloud.sh --provider=aws --check
```

Deploy:

```bash
./scripts/deploy/deploy_cloud.sh --provider=azure
./scripts/deploy/deploy_cloud.sh --provider=aws
./scripts/deploy/deploy_cloud.sh --provider=both
```

## Heartbeat Agent

Start the local heartbeat process:

```bash
./scripts/start_heartbeat.sh
```

Stop it:

```bash
./scripts/stop_heartbeat.sh
```

## Expected Environment Variables

- `ALERT_EMAIL`
- `HEARTBEAT_URL`
- `HEARTBEAT_DEVICE`
- `HEARTBEAT_INTERVAL`
- `RG`
- `LOCATION`
- `PREFIX`
- `AWS_REGION`
- `AWS_ACCOUNT`
- `LOG_RETENTION_DAYS`
- `CDK_REMOVAL_POLICY`
