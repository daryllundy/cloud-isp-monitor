#!/bin/bash
set -e

# Source environment variables
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

PREFIX=$(echo $RG | sed 's/-rg$//')
FUNC_APP_NAME="${PREFIX}-func"

echo "Function App: $FUNC_APP_NAME"
echo "Resource Group: $RG"

# Create deployment package
rm -f function.zip
zip -r function.zip . -x ".git/*" ".venv/*" ".history/*" ".kiro/*" ".vscode/*" "*.pyc" "__pycache__/*" ".DS_Store" "*.sh" "main.bicep" ".env" "*.zip" ".env.example"

echo "Package created: $(ls -lh function.zip)"
echo "Testing zipdeploy endpoint..."

# Get publishing credentials
CREDS=$(az functionapp deployment list-publishing-credentials \
  --resource-group "$RG" \
  --name "$FUNC_APP_NAME" \
  --query "{username:publishingUserName, password:publishingPassword}" \
  --output json)

USERNAME=$(echo "$CREDS" | jq -r '.username')
PASSWORD=$(echo "$CREDS" | jq -r '.password')

echo "Username: ${USERNAME:0:10}..."

# Try zipdeploy with verbose output
echo "Deploying with zipdeploy API..."
curl -X POST \
  -u "$USERNAME:$PASSWORD" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @function.zip \
  -w "\nHTTP Status: %{http_code}\n" \
  -v \
  https://$FUNC_APP_NAME.scm.azurewebsites.net/api/zipdeploy

rm -f function.zip
