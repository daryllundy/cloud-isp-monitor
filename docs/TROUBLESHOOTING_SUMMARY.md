# Azure ISP Monitor - Troubleshooting Summary

**Date:** October 17, 2025
**Status:** Deployment Working, Application Insights Integration Pending

---

## Problem Statement

The `deploy.sh` script was failing to deploy the Azure Function code, resulting in the function returning HTTP 404 errors. After fixing the deployment, a secondary issue emerged: Application Insights is not receiving telemetry from the Python function, which prevents the alert system from working.

---

## Root Cause Analysis

### Primary Issue: Incompatible Deployment Method

**Root Cause:** Linux Consumption Plan functions **DO NOT** support `WEBSITE_RUN_FROM_PACKAGE=1`

The original deploy.sh attempted to use "run from package" deployment by:
1. Uploading the zip to blob storage
2. Setting `WEBSITE_RUN_FROM_PACKAGE="1"` or `WEBSITE_RUN_FROM_PACKAGE="<URL>"`

**Critical Finding from Microsoft Documentation:**
> "If you are using a Consumption Service Plan you cannot use WEBSITE_RUN_FROM_PACKAGE on Linux."

This is a platform limitation specific to:
- **Linux-based** Azure Functions
- **Consumption plan** (Y1 SKU)
- The combination of these two factors

### Secondary Issue: Application Insights Telemetry Not Flowing

**Status:** Under Investigation

Despite successful deployment, Application Insights is not receiving any telemetry from the function:
- Function responds with HTTP 200 ✅
- No requests appear in Application Insights ❌
- No traces or logs appear in Application Insights ❌
- Alert cannot trigger without telemetry ❌

**Attempted Solutions:**
1. ✅ Updated `host.json` with extension bundles configuration
2. ✅ Removed conflicting build settings from bicep template
3. ✅ Added `PYTHON_ENABLE_WORKER_EXTENSIONS=1` setting
4. ✅ Added `PYTHON_ENABLE_DEBUG_LOGGING=1` setting
5. ⏳ Waiting for telemetry to flow (can take 2-5 minutes)

---

## Solution: Corrected Deployment Method

### What Changed in deploy.sh

**Before (Broken):**
```bash
# Attempted run-from-package with WEBSITE_RUN_FROM_PACKAGE=1
az functionapp config appsettings set \
  --settings WEBSITE_RUN_FROM_PACKAGE="$PACKAGE_URL"
```

**After (Working):**
```bash
# Upload to blob storage and set full URL
STORAGE_ACCOUNT=$(az storage account list ...)
ACCOUNT_KEY=$(az storage account keys list ...)

# Upload package
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$ACCOUNT_KEY" \
  --container-name "function-releases" \
  --name "$BLOB_NAME" \
  --file function.zip

# Generate SAS token
SAS_TOKEN=$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$ACCOUNT_KEY" \
  --container-name "function-releases" \
  --name "$BLOB_NAME" \
  --permissions r \
  --expiry "$EXPIRY" \
  --https-only)

PACKAGE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/function-releases/${BLOB_NAME}?${SAS_TOKEN}"

# Set the full URL (not "1")
az functionapp config appsettings set \
  --settings WEBSITE_RUN_FROM_PACKAGE="$PACKAGE_URL"
```

### Key Differences

1. **Authentication:** Uses storage account keys instead of managed identity for deployment
2. **URL Format:** Sets full blob URL with SAS token, not "1"
3. **Container Management:** Ensures container exists before upload
4. **SAS Token:** Generates 7-day SAS token for the package

### What Changed in main.bicep

**Build Settings:**
```bicep
appSettings: [
  // ... other settings ...
  // Enable build during zip deployment (required for Linux Consumption)
  { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
  { name: 'ENABLE_ORYX_BUILD', value: 'true' }
]
```

**Removed:** `WEBSITE_RUN_FROM_PACKAGE` from bicep (now set dynamically by deploy.sh)

### What Changed in host.json

**Added Extension Bundles:**
```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": false
      },
      "enableDependencyTracking": true
    },
    "logLevel": {
      "default": "Information",
      "Function": "Information"
    }
  }
}
```

---

## Current Status

### ✅ Working Components

| Component | Status | Details |
|-----------|--------|---------|
| Function Deployment | ✅ Working | HTTP 200 responses |
| Infrastructure | ✅ Working | All Azure resources deployed |
| Alert Configuration | ✅ Working | autoMitigate=true, continuous notifications |
| Action Group | ✅ Working | Email configured and enabled |
| deploy.sh Script | ✅ Working | Successful deployments |

### ❌ Outstanding Issues

| Component | Status | Impact |
|-----------|--------|--------|
| Application Insights Telemetry | ❌ Not Working | No request data flowing |
| Alert Firing | ❌ Blocked | Depends on telemetry |
| End-to-End Testing | ❌ Blocked | Cannot verify alerts |

---

## Next Steps

### Immediate Priority: Fix Application Insights Integration

1. **Verify Python Worker Configuration**
   - Check if `PYTHON_ENABLE_WORKER_EXTENSIONS=1` is effective
   - Verify Azure Functions runtime version compatibility

2. **Check Function Logs**
   ```bash
   az webapp log tail --name darylhome-func --resource-group darylhome-rg
   ```

3. **Manual Telemetry Test**
   - Add explicit Application Insights SDK calls in Python code
   - Verify connection string is accessible by the function

4. **Alternative: Check if telemetry is delayed**
   - Wait 5-10 minutes and recheck
   - Application Insights can have ingestion delays

### Once Telemetry is Working

1. **Test Alert Firing**
   ```bash
   ./stop_heartbeat.sh
   # Wait 6-7 minutes
   # Check email for alert
   ```

2. **Test Alert Resolution**
   ```bash
   ./start_heartbeat.sh
   # Wait 6-7 minutes
   # Check email for resolution notification
   ```

---

## Technical Notes

### Linux Consumption Plan Limitations

- ❌ Cannot use `WEBSITE_RUN_FROM_PACKAGE=1`
- ✅ Can use `WEBSITE_RUN_FROM_PACKAGE=<full-url-with-sas>`
- ✅ Requires `SCM_DO_BUILD_DURING_DEPLOYMENT=true`
- ✅ Requires `ENABLE_ORYX_BUILD=true`

### Application Insights Configuration

**Required Settings:**
- `APPLICATIONINSIGHTS_CONNECTION_STRING` (set via bicep) ✅
- `APPINSIGHTS_INSTRUMENTATIONKEY` (set via bicep) ✅
- `PYTHON_ENABLE_WORKER_EXTENSIONS=1` (added manually) ✅

**Expected Behavior:**
- Automatic telemetry collection for HTTP requests
- No additional Python packages required for Functions v4+
- Telemetry should appear within 2-5 minutes

### Alert Query Details

```kusto
requests
| where cloud_RoleName == "darylhome-func"
| where name == "Ping"
| where timestamp > ago(5m)
| summarize count()
```

**Alert Triggers When:** count < 1
**Evaluation Frequency:** Every 5 minutes
**Notification Frequency:** Every 5 minutes (continuous during outage)

---

## Lessons Learned

1. **Platform Constraints Matter:** Always check Azure documentation for platform-specific limitations (Linux vs Windows, Consumption vs Premium)

2. **Deployment Methods Vary:** What works for Windows Functions or Premium plans may not work for Linux Consumption plans

3. **Managed Identity vs Keys:** While managed identity is more secure for runtime, deployment still requires account keys for blob operations

4. **Telemetry != Function Success:** A function can respond successfully (HTTP 200) but still fail to send telemetry to Application Insights

5. **Build Settings Are Critical:** `SCM_DO_BUILD_DURING_DEPLOYMENT` and `ENABLE_ORYX_BUILD` are required for Linux Consumption to install Python dependencies

---

## References

- [Azure Functions Python Developer Reference](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Monitor Azure Functions with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/monitor-functions)
- [App Settings Reference for Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings)
- [Linux Consumption Plan Limitations](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale)

---

## File Changes Summary

### Modified Files
- ✅ `deploy.sh` - Complete rewrite of deployment logic
- ✅ `main.bicep` - Updated app settings for Linux Consumption
- ✅ `host.json` - Added extension bundles and logging config

### New Files
- 📄 `TROUBLESHOOTING_SUMMARY.md` (this file)

### Unchanged Files
- `Ping/__init__.py` - Function code (working correctly)
- `requirements.txt` - Dependencies (minimal, as required)
- `.env` - Environment configuration
- Alert scripts (`start_heartbeat.sh`, `stop_heartbeat.sh`)
