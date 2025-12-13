#!/bin/bash
set -e

# Colors for output (with fallback for terminals that don't support colors)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZURE_SCRIPT="$SCRIPT_DIR/deploy.sh"
AWS_SCRIPT="$SCRIPT_DIR/deploy_aws.sh"
ENV_FILE="$SCRIPT_DIR/.env"

# Global variables
CLOUD_TARGET=""
CHECK_ONLY=false

#######################################
# Display usage information
#######################################
show_help() {
    cat << EOF
Unified Multi-Cloud Deployment Script for ISP Monitor

Usage: $0 --cloud=<target> [OPTIONS]

Cloud Targets:
  --cloud=azure         Deploy to Azure only
  --cloud=aws           Deploy to AWS only
  --cloud=both          Deploy to both Azure and AWS (sequential)

Options:
  --check               Validate prerequisites without deploying
  --help                Show this help message

Examples:
  $0 --cloud=azure      Deploy to Azure
  $0 --cloud=aws        Deploy to AWS
  $0 --cloud=both       Deploy to both clouds
  $0 --cloud=azure --check    Check Azure prerequisites only

Prerequisites:
  Azure: Azure CLI (az), jq, zip
  AWS:   AWS CLI, Node.js, npm, Python 3.8+

Configuration:
  Create a .env file from .env.example with cloud-specific variables:
  - Azure: RG, LOCATION, ALERT_EMAIL
  - AWS:   AWS_REGION, ALERT_EMAIL, PREFIX

Traditional Deployment (Still Supported):
  ./deploy.sh          Deploy to Azure directly
  ./deploy_aws.sh      Deploy to AWS directly

EOF
}

#######################################
# Print error message and exit
#######################################
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

#######################################
# Print success message
#######################################
success_msg() {
    echo -e "${GREEN}$1${NC}"
}

#######################################
# Print warning message
#######################################
warning_msg() {
    echo -e "${YELLOW}$1${NC}"
}

#######################################
# Print info message
#######################################
info_msg() {
    echo -e "${BLUE}$1${NC}"
}

#######################################
# Check if a command exists
#######################################
check_command() {
    local cmd=$1
    local install_hint=$2

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} $cmd not found"
        if [ -n "$install_hint" ]; then
            echo "  Install: $install_hint"
        fi
        return 1
    else
        echo -e "${GREEN}✓${NC} $cmd found"
        return 0
    fi
}

#######################################
# Check Azure prerequisites
#######################################
check_azure_prereqs() {
    echo ""
    info_msg "Checking Azure prerequisites..."
    echo ""

    local all_ok=true

    # Check Azure CLI
    if ! check_command "az" "https://docs.microsoft.com/cli/azure/install-azure-cli"; then
        all_ok=false
    fi

    # Check jq
    if ! check_command "jq" "brew install jq (macOS) or apt-get install jq (Linux)"; then
        all_ok=false
    fi

    # Check zip
    if ! check_command "zip" "Included with most systems"; then
        all_ok=false
    fi

    # Check authentication
    if [ "$all_ok" = true ]; then
        echo ""
        echo "Checking Azure authentication..."
        if az account show >/dev/null 2>&1; then
            AZURE_ACCOUNT=$(az account show --query name -o tsv 2>/dev/null || echo "Unknown")
            echo -e "${GREEN}✓${NC} Authenticated to Azure"
            echo "  Account: $AZURE_ACCOUNT"
        else
            echo -e "${RED}✗${NC} Not authenticated to Azure"
            echo "  Run: az login"
            all_ok=false
        fi
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        success_msg "Azure prerequisites: OK"
        return 0
    else
        error_exit "Azure prerequisites check failed"
    fi
}

#######################################
# Check AWS prerequisites
#######################################
check_aws_prereqs() {
    echo ""
    info_msg "Checking AWS prerequisites..."
    echo ""

    local all_ok=true

    # Check AWS CLI
    if ! check_command "aws" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; then
        all_ok=false
    fi

    # Check Node.js (required for CDK)
    if ! check_command "node" "brew install node (macOS) or https://nodejs.org"; then
        all_ok=false
    fi

    # Check npm
    if ! check_command "npm" "Included with Node.js"; then
        all_ok=false
    fi

    # Check Python 3
    if ! check_command "python3" "brew install python3 (macOS) or apt-get install python3 (Linux)"; then
        all_ok=false
    fi

    # Check jq (for parsing outputs)
    if ! check_command "jq" "brew install jq (macOS) or apt-get install jq (Linux)"; then
        all_ok=false
    fi

    # Check authentication
    if [ "$all_ok" = true ]; then
        echo ""
        echo "Checking AWS authentication..."
        if aws sts get-caller-identity >/dev/null 2>&1; then
            AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
            AWS_REGION_CURRENT=$(aws configure get region 2>/dev/null || echo "Not set")
            echo -e "${GREEN}✓${NC} Authenticated to AWS"
            echo "  Account: $AWS_ACCOUNT"
            echo "  Default Region: $AWS_REGION_CURRENT"
        else
            echo -e "${RED}✗${NC} Not authenticated to AWS"
            echo "  Run: aws configure"
            all_ok=false
        fi
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        success_msg "AWS prerequisites: OK"
        return 0
    else
        error_exit "AWS prerequisites check failed"
    fi
}

#######################################
# Validate .env file exists
#######################################
check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        error_exit ".env file not found. Run: cp .env.example .env"
    fi
}

#######################################
# Validate Azure environment variables
#######################################
validate_azure_env() {
    echo ""
    info_msg "Validating Azure configuration..."

    # Load .env
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi

    local missing=()
    [ -z "$RG" ] && missing+=("RG")
    [ -z "$LOCATION" ] && missing+=("LOCATION")
    [ -z "$ALERT_EMAIL" ] && missing+=("ALERT_EMAIL")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}✗${NC} Missing required Azure variables in .env:"
        printf '  - %s\n' "${missing[@]}"
        echo ""
        echo "Add these to your .env file:"
        echo "  RG=your-resource-group-name"
        echo "  LOCATION=westus2"
        echo "  ALERT_EMAIL=your-email@example.com"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Azure configuration valid"
    echo "  Resource Group: $RG"
    echo "  Location: $LOCATION"
    echo "  Alert Email: $ALERT_EMAIL"
}

#######################################
# Validate AWS environment variables
#######################################
validate_aws_env() {
    echo ""
    info_msg "Validating AWS configuration..."

    # Load .env
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    fi

    local missing=()
    [ -z "$AWS_REGION" ] && missing+=("AWS_REGION")
    [ -z "$ALERT_EMAIL" ] && missing+=("ALERT_EMAIL")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}✗${NC} Missing required AWS variables in .env:"
        printf '  - %s\n' "${missing[@]}"
        echo ""
        echo "Add these to your .env file:"
        echo "  AWS_REGION=us-east-1"
        echo "  ALERT_EMAIL=your-email@example.com"
        echo "  PREFIX=isp-monitor"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} AWS configuration valid"
    echo "  AWS Region: $AWS_REGION"
    echo "  Alert Email: $ALERT_EMAIL"
    echo "  Prefix: ${PREFIX:-isp-monitor}"
}

#######################################
# Deploy to Azure
#######################################
deploy_azure() {
    echo ""
    echo "=========================================="
    info_msg "Deploying to Azure"
    echo "=========================================="
    echo ""

    if [ ! -x "$AZURE_SCRIPT" ]; then
        error_exit "Azure deployment script not found or not executable: $AZURE_SCRIPT"
    fi

    # Execute Azure deployment script
    "$AZURE_SCRIPT"

    return $?
}

#######################################
# Deploy to AWS
#######################################
deploy_aws() {
    echo ""
    echo "=========================================="
    info_msg "Deploying to AWS"
    echo "=========================================="
    echo ""

    if [ ! -x "$AWS_SCRIPT" ]; then
        error_exit "AWS deployment script not found or not executable: $AWS_SCRIPT"
    fi

    # Execute AWS deployment script
    "$AWS_SCRIPT"

    return $?
}

#######################################
# Deploy to both clouds
#######################################
deploy_both() {
    local azure_success=false
    local aws_success=false

    echo ""
    echo "=========================================="
    info_msg "Multi-Cloud Deployment"
    echo "=========================================="
    echo "Target: Azure + AWS"
    echo "Mode: Sequential deployment"
    echo "=========================================="

    # Deploy to Azure
    echo ""
    info_msg "[1/2] Starting Azure deployment..."
    if deploy_azure; then
        azure_success=true
        success_msg "Azure deployment completed successfully"
    else
        warning_msg "Azure deployment failed"
    fi

    # Deploy to AWS
    echo ""
    info_msg "[2/2] Starting AWS deployment..."
    if deploy_aws; then
        aws_success=true
        success_msg "AWS deployment completed successfully"
    else
        warning_msg "AWS deployment failed"
    fi

    # Summary
    echo ""
    echo "=========================================="
    info_msg "Multi-Cloud Deployment Summary"
    echo "=========================================="
    if [ "$azure_success" = true ]; then
        echo -e "Azure: ${GREEN}✓ Success${NC}"
    else
        echo -e "Azure: ${RED}✗ Failed${NC}"
    fi

    if [ "$aws_success" = true ]; then
        echo -e "AWS:   ${GREEN}✓ Success${NC}"
    else
        echo -e "AWS:   ${RED}✗ Failed${NC}"
    fi
    echo "=========================================="
    echo ""

    # Exit with error if any deployment failed
    if [ "$azure_success" = false ] || [ "$aws_success" = false ]; then
        exit 1
    fi

    return 0
}

#######################################
# Parse command-line arguments
#######################################
parse_args() {
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi

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
                echo "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    # Validate cloud target
    if [ -z "$CLOUD_TARGET" ]; then
        error_exit "Cloud target not specified. Use --cloud=azure, --cloud=aws, or --cloud=both"
    fi

    if [ "$CLOUD_TARGET" != "azure" ] && [ "$CLOUD_TARGET" != "aws" ] && [ "$CLOUD_TARGET" != "both" ]; then
        error_exit "Invalid cloud target: $CLOUD_TARGET. Must be 'azure', 'aws', or 'both'"
    fi
}

#######################################
# Main execution
#######################################
main() {
    # Parse arguments
    parse_args "$@"

    echo ""
    echo "=========================================="
    info_msg "ISP Monitor - Unified Cloud Deployment"
    echo "=========================================="
    echo "Cloud Target: $CLOUD_TARGET"
    echo "Check Only: $CHECK_ONLY"
    echo "=========================================="

    # Check .env file exists
    check_env_file

    # Check prerequisites and validate environment based on target
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

    # If check-only mode, exit here
    if [ "$CHECK_ONLY" = true ]; then
        echo ""
        success_msg "Prerequisite check completed successfully!"
        echo ""
        echo "Ready to deploy. Run without --check flag to deploy:"
        echo "  $0 --cloud=$CLOUD_TARGET"
        exit 0
    fi

    # Execute deployment
    echo ""
    info_msg "Starting deployment..."

    case $CLOUD_TARGET in
        azure)
            deploy_azure
            ;;
        aws)
            deploy_aws
            ;;
        both)
            deploy_both
            ;;
    esac

    # Final success message
    echo ""
    success_msg "Deployment completed successfully!"
    echo ""
}

# Run main function
main "$@"
