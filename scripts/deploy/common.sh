#!/bin/bash

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

success_msg() {
    echo -e "${GREEN}$1${NC}"
}

warning_msg() {
    echo -e "${YELLOW}$1${NC}"
}

info_msg() {
    echo -e "${BLUE}$1${NC}"
}

print_header() {
    echo ""
    echo "=========================================="
    info_msg "$1"
    echo "=========================================="
}

load_env_file() {
    local env_file=$1
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

require_env_vars() {
    local missing=()
    local var

    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        printf '%s\n' "${missing[@]}"
        return 1
    fi
}

check_command() {
    local cmd=$1
    local install_hint=$2

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} $cmd not found"
        if [ -n "$install_hint" ]; then
            echo "  Install: $install_hint"
        fi
        return 1
    fi

    echo -e "${GREEN}✓${NC} $cmd found"
    return 0
}

check_azure_auth() {
    if az account show >/dev/null 2>&1; then
        local azure_account
        azure_account=$(az account show --query name -o tsv 2>/dev/null || echo "Unknown")
        echo -e "${GREEN}✓${NC} Authenticated to Azure"
        echo "  Account: $azure_account"
        return 0
    fi

    echo -e "${RED}✗${NC} Not authenticated to Azure"
    echo "  Run: az login"
    return 1
}

check_aws_auth() {
    if aws sts get-caller-identity >/dev/null 2>&1; then
        local aws_account
        local aws_region_current
        aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
        aws_region_current=$(aws configure get region 2>/dev/null || echo "Not set")
        echo -e "${GREEN}✓${NC} Authenticated to AWS"
        echo "  Account: $aws_account"
        echo "  Default Region: $aws_region_current"
        return 0
    fi

    echo -e "${RED}✗${NC} Not authenticated to AWS"
    echo "  Run: aws configure"
    return 1
}

verify_http_endpoint() {
    local url=$1
    local label=$2

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        success_msg "$label is responding (HTTP $http_code)"
        return 0
    fi

    if [ "$http_code" = "503" ]; then
        warning_msg "$label is still starting up (HTTP 503)"
        return 1
    fi

    warning_msg "$label returned HTTP $http_code"
    return 1
}
