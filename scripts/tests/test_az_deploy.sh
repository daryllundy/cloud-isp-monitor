#!/bin/bash

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

PREFIX=$(echo $RG | sed 's/-rg$//')
FUNC_APP_NAME="${PREFIX}-func"

echo "Testing Azure CLI deployment method..."
echo "Function App: $FUNC_APP_NAME"
echo "Resource Group: $RG"

az functionapp deployment source config-zip \
  --resource-group "$RG" \
  --name "$FUNC_APP_NAME" \
  --src function.zip
