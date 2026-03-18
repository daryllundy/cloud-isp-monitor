import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CDK_ROOT = REPO_ROOT / "cdk"

for path in (REPO_ROOT, CDK_ROOT):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)
