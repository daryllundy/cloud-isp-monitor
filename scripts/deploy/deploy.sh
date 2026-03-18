#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
load_env_file "$ENV_FILE"

if ! missing=$(require_env_vars RG LOCATION ALERT_EMAIL); then
    error_exit "Missing required Azure variables in .env:\n$missing"
fi

PREFIX="${PREFIX:-$(echo "$RG" | sed 's/-rg$//')}"

print_header "Azure ISP Monitor - Deployment Script"
echo "Resource Group: $RG"
echo "Location: $LOCATION"
echo "Prefix: $PREFIX"
echo "Alert Email: $ALERT_EMAIL"

echo ""
echo "[1/3] Checking resource group..."
if ! az group show --name "$RG" >/dev/null 2>&1; then
    echo "Creating resource group $RG in $LOCATION..."
    az group create --name "$RG" --location "$LOCATION" --output none
    success_msg "Resource group $RG created successfully."
else
    success_msg "Resource group $RG already exists."
fi

echo ""
echo "[2/3] Deploying infrastructure..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RG" \
    --template-file "$REPO_ROOT/main.bicep" \
    --parameters prefix="$PREFIX" alertEmail="$ALERT_EMAIL" \
    --query 'properties.outputs' \
    --output json)

echo "Infrastructure deployed successfully!"
FUNC_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.functionAppName.value // empty')
FUNC_APP_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.functionAppUrl.value // empty')

if [ -z "$FUNC_APP_NAME" ]; then
    FUNC_APP_NAME="${PREFIX}-func"
    FUNC_APP_URL="https://${FUNC_APP_NAME}.azurewebsites.net/api/ping"
fi

echo ""
echo "Verifying alert configuration..."
ALERT_CONFIG=$(az monitor scheduled-query show \
    --name "${PREFIX}-heartbeat-miss" \
    --resource-group "$RG" \
    --query "{muteActions:muteActionsDuration, autoMitigate:autoMitigate}" \
    --output json 2>/dev/null || true)

if [ -n "$ALERT_CONFIG" ]; then
    MUTE_DURATION=$(echo "$ALERT_CONFIG" | jq -r '.muteActions')
    AUTO_MITIGATE=$(echo "$ALERT_CONFIG" | jq -r '.autoMitigate')
    echo "Mute Actions Duration: $MUTE_DURATION"
    echo "Auto Mitigate: $AUTO_MITIGATE"
else
    warning_msg "Could not verify alert configuration yet."
fi

echo ""
echo "[3/3] Deploying function app code..."
check_command "zip" "Included with most systems" >/dev/null
rm -f "$REPO_ROOT/function.zip"
(
    cd "$REPO_ROOT"
    zip -rq function.zip Ping host.json requirements.txt isp_monitor_core
)

STORAGE_ACCOUNT=$(az storage account list \
    --resource-group "$RG" \
    --query "[?starts_with(name, '${PREFIX}sa')].name | [0]" \
    --output tsv)

[ -n "$STORAGE_ACCOUNT" ] || error_exit "Could not determine storage account."

CONTAINER_NAME="function-releases"
BLOB_NAME="function-$(date -u +%Y%m%d%H%M%S).zip"
ACCOUNT_KEY=$(az storage account keys list \
    --resource-group "$RG" \
    --account-name "$STORAGE_ACCOUNT" \
    --query "[0].value" \
    --output tsv)

az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --output none 2>/dev/null || true

az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --container-name "$CONTAINER_NAME" \
    --name "$BLOB_NAME" \
    --file "$REPO_ROOT/function.zip" \
    --overwrite \
    --output none

EXPIRY=$(date -u -v+7d '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -d '+7 days' '+%Y-%m-%dT%H:%MZ')
SAS_TOKEN=$(az storage blob generate-sas \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --container-name "$CONTAINER_NAME" \
    --name "$BLOB_NAME" \
    --permissions r \
    --expiry "$EXPIRY" \
    --https-only \
    --output tsv)

PACKAGE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${BLOB_NAME}?${SAS_TOKEN}"
az functionapp config appsettings set \
    --resource-group "$RG" \
    --name "$FUNC_APP_NAME" \
    --settings WEBSITE_RUN_FROM_PACKAGE="$PACKAGE_URL" \
    --output none

rm -f "$REPO_ROOT/function.zip"
az functionapp restart --resource-group "$RG" --name "$FUNC_APP_NAME" --output none

echo "Waiting for function to start..."
sleep 30
verify_http_endpoint "$FUNC_APP_URL" "Azure Function"

print_header "Deployment Complete"
echo "Function App: $FUNC_APP_NAME"
echo "Function URL: $FUNC_APP_URL"
