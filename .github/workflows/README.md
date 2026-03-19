# GitHub Workflows

Repository-managed deployment workflows have been removed.

Deployments are now performed locally through the canonical script:

```bash
./scripts/deploy/deploy_cloud.sh --provider=<azure|aws|both>
```

Legacy convenience wrappers still exist:

```bash
./scripts/deploy/deploy.sh
./scripts/deploy/deploy_aws.sh
```
