# Repository Guidelines

## Project Structure & Module Organization
- `Ping/` contains the production Azure Function: `__init__.py` handles validation/logging; `function.json` defines the HTTP trigger signature.
- `heartbeat_agent.py` is the on-device client; pair with `start_heartbeat.sh`/`stop_heartbeat.sh` for tmux-managed runs.
- `main.bicep` and `deploy.sh` orchestrate Azure resources; supporting scripts (`test_*.sh`, `deploy.sh`) expect `.env` populated with RG, LOCATION, HEARTBEAT_* values.
- `requirements.txt`, `host.json`, and `local.settings.json` align with the Azure Functions Python runtime; keep secrets in `.env`, never in Git.

## Build, Test, and Development Commands
- `python3 -m pip install -r requirements.txt` installs the minimal runtime dependencies used by the function.
- `./deploy.sh` deploys or updates infrastructure and functions via Bicep (requires Azure CLI login).
- `./test_deploy.sh` performs a dry-run validation of the deployment scripts without applying changes.
- `./test_alerts.sh` verifies the monitor rule/action group configuration after deployment; run whenever alert settings change.
- `./start_heartbeat.sh` / `./stop_heartbeat.sh` manage the agent’s tmux session locally; use `tmux attach -t isp-monitor` to inspect live logs.

## Coding Style & Naming Conventions
- Python code targets 3.11, uses `azure.functions`, and follows PEP 8 with 4-space indentation; keep input sanitization and logging consistent with `Ping/__init__.py`.
- Name Azure resources with the `{prefix}-{component}` pattern already used in Bicep (`{prefix}-heartbeat-miss`, `{prefix}-ag`).
- CLI scripts are bash with `set -e`; prefer lowercase, hyphenated filenames and descriptive function names (e.g., `print_success`).

## Testing Guidelines
- Shell-based tests rely on Azure CLI, `jq`, and environment variables; export `RG` and related values before running.
- For agent changes, run `python3 heartbeat_agent.py --once --verbose` against a staging endpoint, then confirm daemon mode with `--daemon --interval 60`.
- When adjusting alert logic, re-run `./test_alerts.sh` and capture output in the PR.

## Commit & Pull Request Guidelines
- Craft short, imperative commit subjects (`Add heartbeat retry logging`); include context in the body when touching deployment or alert logic.
- Reference related issues or deployment tickets in PR descriptions; attach command output snippets or screenshots showing successful `./deploy.sh` or test runs.
- Ensure PRs describe configuration impacts and highlight any manual follow-up steps (certificate installs, secret rotations).

## Security & Configuration Tips
- Never commit `.env`, real values in `local.settings.json`, or certificates; use `.env.example` for sharable defaults.
- Rotate secret slots via Azure Portal or CLI before publishing; note the change in the PR checklist.
- Limit production agent credentials to least privilege and avoid embedding tokens in scripts.
