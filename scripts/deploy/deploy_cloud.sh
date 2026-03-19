#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CDK_ROOT="$REPO_ROOT/cdk"
ENV_FILE="$REPO_ROOT/.env"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

PROVIDER=""
CHECK_ONLY=false

show_help() {
    cat << EOF
Unified ISP Monitor deployment script

Usage: $0 --provider=<target> [OPTIONS]

Providers:
  --provider=azure      Deploy to Azure only
  --provider=aws        Deploy to AWS only
  --provider=both       Deploy to both Azure and AWS

Options:
  --check               Validate prerequisites without deploying
  --help                Show this help message

Compatibility:
  --cloud=<target>      Deprecated alias for --provider
EOF
}

check_env_file() {
    [ -f "$ENV_FILE" ] || error_exit ".env file not found. Run: cp .env.example .env"
}

check_azure_prereqs() {
    print_header "Checking Azure prerequisites"
    local all_ok=true

    check_command "az" "https://docs.microsoft.com/cli/azure/install-azure-cli" || all_ok=false
    check_command "jq" "brew install jq" || all_ok=false
    check_command "zip" "Included with most systems" || all_ok=false
    if [ "$all_ok" = true ]; then
        check_azure_auth || all_ok=false
    fi

    [ "$all_ok" = true ] || error_exit "Azure prerequisites check failed"
}

check_aws_prereqs() {
    print_header "Checking AWS prerequisites"
    local all_ok=true

    check_command "aws" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" || all_ok=false
    check_command "node" "https://nodejs.org" || all_ok=false
    check_command "npm" "Included with Node.js" || all_ok=false
    check_command "python3" "Install Python 3" || all_ok=false
    check_command "jq" "brew install jq" || all_ok=false
    if [ "$all_ok" = true ]; then
        check_aws_auth || all_ok=false
    fi

    [ "$all_ok" = true ] || error_exit "AWS prerequisites check failed"
}

run_provider_checks() {
    local provider=$1

    case "$provider" in
        azure)
            check_azure_prereqs
            validate_provider_env azure
            ;;
        aws)
            check_aws_prereqs
            validate_provider_env aws
            ;;
        both)
            check_azure_prereqs
            check_aws_prereqs
            validate_provider_env azure
            validate_provider_env aws
            ;;
        *)
            error_exit "Unknown provider: $provider"
            ;;
    esac
}

deploy_azure() {
    local prefix func_app_name func_app_url deployment_output alert_config
    local mute_duration auto_mitigate storage_account container_name blob_name account_key
    local expiry sas_token package_url

    validate_provider_env azure

    prefix="${PREFIX:-$(echo "$RG" | sed 's/-rg$//')}"

    print_header "Azure ISP Monitor - Deployment Script"
    echo "Resource Group: $RG"
    echo "Location: $LOCATION"
    echo "Prefix: $prefix"
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
    deployment_output=$(az deployment group create \
        --resource-group "$RG" \
        --template-file "$REPO_ROOT/main.bicep" \
        --parameters prefix="$prefix" alertEmail="$ALERT_EMAIL" \
        --query 'properties.outputs' \
        --output json)

    echo "Infrastructure deployed successfully!"
    func_app_name=$(echo "$deployment_output" | jq -r '.functionAppName.value // empty')
    func_app_url=$(echo "$deployment_output" | jq -r '.functionAppUrl.value // empty')

    if [ -z "$func_app_name" ]; then
        func_app_name="${prefix}-func"
        func_app_url="https://${func_app_name}.azurewebsites.net/api/ping"
    fi

    echo ""
    echo "Verifying alert configuration..."
    alert_config=$(az monitor scheduled-query show \
        --name "${prefix}-heartbeat-miss" \
        --resource-group "$RG" \
        --query "{muteActions:muteActionsDuration, autoMitigate:autoMitigate}" \
        --output json 2>/dev/null || true)

    if [ -n "$alert_config" ]; then
        mute_duration=$(echo "$alert_config" | jq -r '.muteActions')
        auto_mitigate=$(echo "$alert_config" | jq -r '.autoMitigate')
        echo "Mute Actions Duration: $mute_duration"
        echo "Auto Mitigate: $auto_mitigate"
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

    storage_account=$(az storage account list \
        --resource-group "$RG" \
        --query "[?starts_with(name, '${prefix}sa')].name | [0]" \
        --output tsv)

    [ -n "$storage_account" ] || error_exit "Could not determine storage account."

    container_name="function-releases"
    blob_name="function-$(date -u +%Y%m%d%H%M%S).zip"
    account_key=$(az storage account keys list \
        --resource-group "$RG" \
        --account-name "$storage_account" \
        --query "[0].value" \
        --output tsv)

    az storage container create \
        --name "$container_name" \
        --account-name "$storage_account" \
        --account-key "$account_key" \
        --output none 2>/dev/null || true

    az storage blob upload \
        --account-name "$storage_account" \
        --account-key "$account_key" \
        --container-name "$container_name" \
        --name "$blob_name" \
        --file "$REPO_ROOT/function.zip" \
        --overwrite \
        --output none

    expiry=$(date -u -v+7d '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -d '+7 days' '+%Y-%m-%dT%H:%MZ')
    sas_token=$(az storage blob generate-sas \
        --account-name "$storage_account" \
        --account-key "$account_key" \
        --container-name "$container_name" \
        --name "$blob_name" \
        --permissions r \
        --expiry "$expiry" \
        --https-only \
        --output tsv)

    package_url="https://${storage_account}.blob.core.windows.net/${container_name}/${blob_name}?${sas_token}"
    az functionapp config appsettings set \
        --resource-group "$RG" \
        --name "$func_app_name" \
        --settings WEBSITE_RUN_FROM_PACKAGE="$package_url" \
        --output none

    rm -f "$REPO_ROOT/function.zip"
    az functionapp restart --resource-group "$RG" --name "$func_app_name" --output none

    echo "Waiting for function to start..."
    sleep 30
    verify_http_endpoint "$func_app_url" "Azure Function"

    print_header "Deployment Complete"
    echo "Function App: $func_app_name"
    echo "Function URL: $func_app_url"
}

deploy_aws() {
    local stack_name outputs function_url function_name topic_arn alarm_name

    validate_provider_env aws

    print_header "AWS ISP Monitor - Deployment Script"
    echo "AWS Region: $AWS_REGION"
    echo "Alert Email: $ALERT_EMAIL"
    echo "Prefix: ${PREFIX:-isp-monitor}"

    echo ""
    echo "Checking AWS CLI authentication..."
    check_aws_auth || error_exit "AWS CLI authentication failed."

    cd "$CDK_ROOT"

    if [ -d ".venv" ]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    fi

    pip install -r requirements.txt >/dev/null

    echo "Bootstrapping CDK..."
    cdk bootstrap

    echo "Deploying stack..."
    cdk deploy --require-approval never

    stack_name=$(cdk list | head -n 1)
    [ -n "$stack_name" ] || error_exit "Could not determine deployed stack name."

    outputs=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs" --output json)
    function_url=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
    function_name=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
    topic_arn=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="TopicArn") | .OutputValue')
    alarm_name=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="AlarmName") | .OutputValue')

    if [ -n "$function_url" ] && [ "$function_url" != "null" ]; then
        echo ""
        echo "Testing Lambda function endpoint..."
        curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"device":"test-deployment","note":"post-deployment verification"}' >/dev/null
        verify_http_endpoint "$function_url" "Lambda Function URL"
    else
        warning_msg "Could not retrieve Function URL from stack outputs."
    fi

    print_header "Configuration Summary"
    echo "Stack Name:   $stack_name"
    echo "Function:     $function_name"
    echo "Function URL: $function_url"
    echo "Topic ARN:    $topic_arn"
    echo "Alarm Name:   $alarm_name"
}

parse_args() {
    [ $# -gt 0 ] || {
        show_help
        exit 1
    }

    while [[ $# -gt 0 ]]; do
        case $1 in
            --provider=*)
                PROVIDER="${1#*=}"
                shift
                ;;
            --cloud=*)
                warning_msg "--cloud is deprecated; use --provider instead."
                PROVIDER="${1#*=}"
                shift
                ;;
            --check)
                CHECK_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done

    case "$PROVIDER" in
        azure|aws|both) ;;
        *) error_exit "Use --provider=azure, --provider=aws, or --provider=both" ;;
    esac
}

main() {
    parse_args "$@"
    check_env_file
    load_env_file "$ENV_FILE"

    print_header "ISP Monitor - Unified Cloud Deployment"
    echo "Provider Target: $PROVIDER"
    echo "Check Only: $CHECK_ONLY"

    run_provider_checks "$PROVIDER"

    if [ "$CHECK_ONLY" = true ]; then
        success_msg "Prerequisite check completed successfully."
        exit 0
    fi

    case "$PROVIDER" in
        azure)
            deploy_azure
            ;;
        aws)
            deploy_aws
            ;;
        both)
            deploy_azure
            deploy_aws
            ;;
    esac

    success_msg "Deployment completed successfully."
}

main "$@"
