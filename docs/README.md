# Documentation

This folder contains all project documentation for the ISP Monitor system.

## Quick Links

### Getting Started
- [Main README](../README.md) - Multi-cloud deployment guide
- [AWS README](README_AWS.md) - AWS deployment guide
- [Platform Comparison](PLATFORM_COMPARISON.md) - Azure vs AWS detailed comparison
- [Migration Guide](MIGRATION_GUIDE.md) - How to migrate from Azure to AWS
- [Developer Workflow](DEVELOPER_WORKFLOW.md) - Local setup, tests, and deploy commands

### Agent Documentation
- [Agent README](AGENT_README.md) - Heartbeat agent setup and usage
- [Agent Guidelines](AGENTS.md) - Development guidelines for the agent

### Operations
- [Scripts Documentation](SCRIPTS.md) - All helper scripts explained
- [Alert Troubleshooting](ALERT_TROUBLESHOOTING.md) - Debugging alert issues

### Security
- [Security Review (AWS)](SECURITY_REVIEW.md) - AWS security analysis
- [Security Documentation (Azure)](SECURITY.md) - Azure security measures

### Deployment & Testing
- [E2E Verification Checklist](E2E_VERIFICATION_CHECKLIST.md) - Verification steps
- [Testing Documentation](../tests/README.md) - Test suite documentation

### Historical Reference
- [History Index](history/README.md) - Archived rollout, status, and reference material

## Document Organization

### Platform-Specific
- **Azure**: Main README.md, SECURITY.md
- **AWS**: README_AWS.md, SECURITY_REVIEW.md
- **Both**: PLATFORM_COMPARISON.md, MIGRATION_GUIDE.md

### By Topic
- **Setup**: Main README, AWS README, Migration Guide
- **Operations**: Scripts, Alert Troubleshooting, Agent README
- **Security**: Security Review, Security Documentation
- **Testing**: Developer Workflow, E2E Verification Checklist

## Contributing

When adding new documentation:
1. Place it in this `docs/` folder
2. Update this README with a link
3. Update cross-references in related documents
4. Use relative paths for links (e.g., `../README.md` for root files)
