# Security Documentation

## Security Improvements Implemented

This document outlines the security measures implemented in the Azure ISP Monitor project.

### 1. Configuration Management

**Fixed: Hardcoded Credentials**
- ✅ Removed hardcoded Function URL from `start_heartbeat.sh`
- ✅ Moved all sensitive configuration to `.env` file (gitignored)
- ✅ Added `.env.example` as template without sensitive data
- ✅ Scripts validate required environment variables before execution

**Configuration in `.env`:**
```bash
HEARTBEAT_URL=https://your-func.azurewebsites.net/api/ping
HEARTBEAT_DEVICE=your-device-name
HEARTBEAT_INTERVAL=60
```

### 2. Input Validation & Sanitization

**Fixed: Log Injection & Unvalidated Input**

The Ping function (`Ping/__init__.py`) now includes:

- ✅ **String Sanitization**: Removes control characters (newlines, special chars) that could cause log injection
- ✅ **Length Limits**:
  - Device name: 100 characters max
  - Note field: 500 characters max
- ✅ **IP Validation**: Validates IPv4/IPv6 format and extracts first IP from X-Forwarded-For chain
- ✅ **Type Checking**: Validates input types before processing

**Implementation:**
```python
def sanitize_string(value, max_length, default="unknown"):
    """Sanitize and validate string input."""
    if not value or not isinstance(value, str):
        return default
    # Remove control characters and limit length
    sanitized = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', value.strip())
    return sanitized[:max_length] if sanitized else default
```

### 3. Azure Managed Identity (Zero Keys)

**Fixed: Storage Account Key Exposure**

Instead of storing account keys in app settings, we now use Azure Managed Identity:

- ✅ **System-Assigned Managed Identity** enabled on Function App
- ✅ **Role Assignments** configured for storage access:
  - Storage Blob Data Owner
  - Storage Queue Data Contributor
  - Storage Table Data Contributor
- ✅ **No secrets in configuration** - authentication happens via Azure AD

**Benefits:**
- No account keys stored in environment variables
- Automatic credential rotation by Azure
- Keys never appear in deployment logs or backups
- Reduced attack surface

### 4. TLS & Transport Security

**Fixed: Missing TLS Configuration**

- ✅ **Minimum TLS 1.2** enforced on Function App
- ✅ **FTPS Disabled** - no insecure file transfer protocols
- ✅ **HTTPS Only** - all HTTP traffic redirected to HTTPS
- ✅ **CORS Policy** - Empty allowed origins list (add specific domains if needed)

**Configuration in `main.bicep`:**
```bicep
siteConfig: {
  minTlsVersion: '1.2'
  ftpsState: 'Disabled'
  cors: {
    allowedOrigins: []
    supportCredentials: false
  }
}
```

### 5. Dependency Management

**Fixed: Unpinned Dependencies**

- ✅ **Version Pinning**: All dependencies pinned to specific versions
- ✅ **Reproducible Builds**: Same versions across all environments
- ✅ **Security**: Prevents automatic updates to vulnerable versions

**requirements.txt:**
```
azure-functions==1.20.0
```

### 6. Authentication Configuration

**Current State: Anonymous Access**

The `/api/ping` endpoint is currently configured with `authLevel: anonymous` for ease of testing.

**For Production:**

Consider changing to `authLevel: function` in `Ping/function.json`:

```json
{
  "authLevel": "function",
  "type": "httpTrigger",
  ...
}
```

Then access with:
```bash
curl https://your-func.azurewebsites.net/api/ping?code=<function-key>
```

Get the function key:
```bash
az functionapp keys list --name <func-name> --resource-group <rg>
```

### 7. Git Security

**Sensitive Files Excluded:**

Comprehensive `.gitignore` includes:
- ✅ `.env` and `.env.*` files
- ✅ Virtual environments (`.venv/`)
- ✅ Deployment packages (`*.zip`)
- ✅ Python cache files
- ✅ IDE configurations
- ✅ Azure CLI configurations
- ✅ Logs and temporary files

## Security Best Practices

### For Developers

1. **Never commit `.env` files** - Use `.env.example` as template
2. **Rotate secrets regularly** - Though we use Managed Identity, rotate Function keys
3. **Review dependencies** - Check for CVEs before updating packages
4. **Validate all input** - Never trust user-provided data
5. **Use HTTPS only** - Never disable TLS/HTTPS

### For Deployment

1. **Enable function-level authentication** before production use
2. **Add IP restrictions** if function should only be accessed from specific networks
3. **Monitor Application Insights** for unusual activity patterns
4. **Set up Azure Security Center** alerts for the resource group
5. **Review role assignments** - Follow principle of least privilege

### For Operations

1. **Monitor alert emails** - Don't ignore security alerts
2. **Audit access logs** in Application Insights regularly
3. **Keep Azure CLI updated** - `az upgrade`
4. **Review deployed resources** monthly for unused/orphaned resources
5. **Test incident response** - Know how to quickly disable a compromised function

## Remaining Security Considerations

### Low Priority Items

1. **Rate Limiting**: Consider adding Azure API Management if concerned about abuse
2. **DDoS Protection**: Consumption plan has basic protection; consider Premium plan for advanced protection
3. **Web Application Firewall**: Not applicable for simple API, but consider if adding web UI
4. **Private Endpoints**: Current setup uses public endpoints; consider VNET integration for internal-only access

### Optional Enhancements

1. **Azure Key Vault**: Store connection strings in Key Vault (currently using Managed Identity which is better)
2. **Azure Front Door**: Add CDN/WAF layer if scaling to many devices
3. **Alert Throttling**: Current implementation has 5-minute mute duration (line 113 in main.bicep)
4. **Geo-Redundancy**: Single region deployment; consider multi-region for critical monitoring

## Threat Model

### Protected Against

✅ **Log Injection** - Input sanitization prevents malicious log entries
✅ **Credential Theft** - No credentials stored (Managed Identity)
✅ **Man-in-the-Middle** - TLS 1.2+ enforced
✅ **Unauthorized Access** - Can enable function keys (currently anonymous for testing)
✅ **Supply Chain Attacks** - Dependency versions pinned
✅ **Data Exfiltration** - No sensitive data logged

### Minimal Risk

⚠️ **DoS via Spam** - Consumption plan has cost implications but no service disruption
⚠️ **IP Spoofing** - X-Forwarded-For validated but can still be spoofed (low impact)

### Not Protected (By Design)

❌ **Public Discovery** - Function URL is publicly discoverable (add auth for protection)
❌ **Brute Force** - No rate limiting on anonymous endpoint (add function keys)

## Compliance Notes

- **Data Residency**: Deployed to specified Azure region (configurable via `.env`)
- **Data Retention**: Application Insights default retention (90 days)
- **Logging**: Heartbeat data (timestamp, device, IP, note) logged to App Insights
- **PII**: Email address used only for alerts (stored in Action Group)

## Security Contacts

For security issues, please:
1. Do NOT create public GitHub issues
2. Contact the repository owner directly
3. Follow responsible disclosure practices

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-10-16 | Initial security hardening | Security Review |
| 2025-10-16 | Added Managed Identity | Security Review |
| 2025-10-16 | Added input validation | Security Review |
| 2025-10-16 | Removed hardcoded credentials | Security Review |
