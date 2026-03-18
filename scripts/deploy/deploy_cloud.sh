#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
AZURE_SCRIPT="$SCRIPT_DIR/deploy.sh"
AWS_SCRIPT="$SCRIPT_DIR/deploy_aws.sh"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CLOUD_TARGET=""
CHECK_ONLY=false

show_help() {
    cat << EOF
Unified Multi-Cloud Deployment Script for ISP Monitor

Usage: $0 --cloud=<target> [OPTIONS]

Cloud Targets:
  --cloud=azure         Deploy to Azure only
  --cloud=aws           Deploy to AWS only
  --cloud=both          Deploy to both Azure and AWS

Options:
  --check               Validate prerequisites without deploying
  --help                Show this help message
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

validate_azure_env() {
    load_env_file "$ENV_FILE"
    if ! missing=$(require_env_vars RG LOCATION ALERT_EMAIL); then
        error_exit "Missing required Azure variables in .env:\n$missing"
    fi
}

validate_aws_env() {
    load_env_file "$ENV_FILE"
    if ! missing=$(require_env_vars AWS_REGION ALERT_EMAIL); then
        error_exit "Missing required AWS variables in .env:\n$missing"
    fi
}

parse_args() {
    [ $# -gt 0 ] || {
        show_help
        exit 1
    }

    while [[ $# -gt 0 ]]; do
        case $1 in
            --cloud=*)
                CLOUD_TARGET="${1#*=}"
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

    case "$CLOUD_TARGET" in
        azure|aws|both) ;;
        *) error_exit "Use --cloud=azure, --cloud=aws, or --cloud=both" ;;
    esac
}

deploy_azure() {
    "$AZURE_SCRIPT"
}

deploy_aws() {
    "$AWS_SCRIPT"
}

main() {
    parse_args "$@"
    check_env_file

    print_header "ISP Monitor - Unified Cloud Deployment"
    echo "Cloud Target: $CLOUD_TARGET"
    echo "Check Only: $CHECK_ONLY"

    case $CLOUD_TARGET in
        azure)
            check_azure_prereqs
            validate_azure_env
            ;;
        aws)
            check_aws_prereqs
            validate_aws_env
            ;;
        both)
            check_azure_prereqs
            check_aws_prereqs
            validate_azure_env
            validate_aws_env
            ;;
    esac

    if [ "$CHECK_ONLY" = true ]; then
        success_msg "Prerequisite check completed successfully."
        exit 0
    fi

    case $CLOUD_TARGET in
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
