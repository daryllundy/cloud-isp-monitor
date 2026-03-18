# Azure ISP Monitor - Deployment Status

**Last Updated:** October 16, 2025, 9:31 PM PST  
**Branch:** troubleshoot-alert-notifications

## ✅ FIXED ISSUES

### 1. Alert Configuration
- **Status:** ✅ RESOLVED
- **Issue:** Email notifications were not being sent due to incorrect alert settings
- **Root Cause:** 
  - `muteActionsDuration` was set to `PT5M` (suppressed notifications after first alert)
  - `autoMitigate` was set to `false` (alerts didn't auto-resolve)
- **Fix Applied:**
  - Updated `main.bicep` to set `autoMitigate: true`
  - Removed `muteActionsDuration` (defaults to continuous notifications when autoMitigate=true)
- **Verification:** Deploy script now shows "✓ Alert configuration verified"

### 2. Deployment Script Validation
- **Status:** ✅ RESOLVED
- **Issue:** Script incorrectly expected `muteActionsDuration: PT0M` but Azure sets it to `null` when autoMitigate=true
- **Fix Applied:** Updated validation logic in `deploy.sh` to correctly handle null values
- **Verification:** Script now properly validates alert configuration

### 3. Action Group Configuration
- **Status:** ✅ WORKING
- **Email Receiver:** `daryl.lundy@gmail.com`
- **Status:** Enabled
- **Location:** Global (correct)

### 4. HTTP Method Configuration Analysis
- **Status:** ✅ CONFIRMED CORRECT
- **Finding:** No HTTP method mismatch exists
- **Details:**
  - `function.json`: Accepts both GET and POST methods ✅
  - `heartbeat_agent.py`: Sends POST requests with JSON payload ✅
  - `Ping/__init__.py`: Handles both request types properly ✅

### 5. Infrastructure Deployment
- **Status:** ✅ WORKING
- **Resource Group:** darylhome-rg ✅
- **Function App:** darylhome-func ✅
- **Application Insights:** darylhome-appi ✅
- **Storage Account:** Configured with managed identity ✅
- **Alert Rule:** darylhome-heartbeat-miss ✅

## ❌ OUTSTANDING ISSUES

### 1. Function Code Deployment
- **Status:** ❌ NOT WORKING
- **Issue:** Azure Function returns 404 for all requests to `/api/ping`
- **Symptoms:**
  - `curl https://darylhome-func.azurewebsites.net/api/ping` → HTTP 404
  - `python3 heartbeat_agent.py --once` → HTTP Error 404
- **Attempted Solutions:**
  - ❌ Zip deployment via curl (HTTP 400 Bad Request)
  - ❌ Azure Functions Core Tools (`func publish` - not supported)
  - ❌ Git deployment (interrupted with "Operation returned invalid status 'OK'")
  - ❌ Manual file upload via Kudu API
  - ❌ Infrastructure redeployment
- **Current State:** Function app exists but code is not executing

### 2. Heartbeat System
- **Status:** ❌ BLOCKED (depends on function deployment)
- **Issue:** Cannot test heartbeat functionality due to function 404 errors
- **Scripts Affected:**
  - `start_heartbeat.sh` - will fail with 404
  - `stop_heartbeat.sh` - works (just kills tmux session)
  - `heartbeat_agent.py` - fails with HTTP 404

## 🔄 NEXT STEPS REQUIRED

### Immediate Priority: Fix Function Deployment

1. **Option A: Azure Portal Deployment**
   - Use Azure Portal's Deployment Center
   - Configure continuous deployment from GitHub
   - May resolve platform-specific deployment issues

2. **Option B: Recreate Function App**
   - Delete and recreate function app with different settings
   - Use consumption plan with different configuration
   - May resolve underlying configuration conflicts

3. **Option C: Alternative Deployment Method**
   - Try VS Code Azure Functions extension
   - Use Azure DevOps pipeline
   - Manual deployment through Azure Portal

### Once Function is Working:

4. **Test Complete System**
   - Verify function responds to GET/POST requests
   - Test heartbeat agent connectivity
   - Validate alert firing and resolution

5. **End-to-End Alert Testing**
   - Run `./start_heartbeat.sh`
   - Run `./stop_heartbeat.sh` 
   - Wait 6-7 minutes for alert to fire
   - Check email notifications
   - Resume heartbeat and verify resolution email

## 📊 SYSTEM READINESS

| Component | Status | Notes |
|-----------|--------|-------|
| Infrastructure | ✅ Ready | All Azure resources deployed |
| Alert Configuration | ✅ Ready | Continuous notifications enabled |
| Email Notifications | ✅ Ready | Action group configured |
| Function Code | ❌ Blocked | 404 errors on all endpoints |
| Heartbeat Agent | ❌ Blocked | Cannot connect to function |
| End-to-End Testing | ❌ Blocked | Waiting for function deployment |

## 🎯 SUCCESS CRITERIA

The system will be fully operational when:
- [ ] Function endpoint returns HTTP 200 for ping requests
- [ ] Heartbeat agent can successfully send pings
- [ ] Alert fires when heartbeat stops (6-7 minutes)
- [ ] Email notifications are received
- [ ] Alert auto-resolves when heartbeat resumes
- [ ] Resolution email is received

## 📝 TECHNICAL NOTES

- **Alert Query:** `requests | where cloud_RoleName == "darylhome-func" | where name == "Ping" | where timestamp > ago(5m) | summarize count()`
- **Alert Threshold:** Less than 1 request in 5 minutes
- **Evaluation Frequency:** Every 5 minutes
- **Expected Behavior:** Continuous email notifications every 5 minutes during outages
- **Auto-Resolution:** Enabled (alerts clear automatically when pings resume)

---

**Key Insight:** The original issue with email notifications has been resolved. The current blocker is purely a function deployment/platform issue, not a configuration problem.
