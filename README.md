# Application Gateway WAF - Synapse Access Control POC

## Overview

This proof-of-concept demonstrates using **Azure Application Gateway with WAF v2 as a reverse proxy** to control access to Azure Synapse Analytics. Unlike the firewall approach, this solution:

- ✅ Uses Application Gateway WAF custom rules to block specific URL paths
- ✅ Acts as a reverse proxy between users and Synapse
- ✅ Keeps Synapse completely private (no public access)
- ✅ Blocks `/sparkhistory/` and `/monitoring/workloadTypes/spark/` paths
- ✅ Allows all other Synapse functionality
- ✅ No TLS inspection configuration needed

### Architecture

```
User VM (10.200.3.0/24)
    ↓ (via hosts file DNS override)
Application Gateway WAF v2 (10.200.1.0/24)
    ├─ WAF Custom Rule 1: Block /sparkhistory/*
    └─ WAF Custom Rule 2: Block /monitoring/workloadTypes/spark/*
    ↓ (reverse proxy via HTTPS)
Synapse Private Endpoint (10.200.2.0/24)
    ↓
Synapse Workspace (fully private, no public access)
```

## Key Differences from Firewall Approach

| Aspect | Firewall + TLS Inspection | Application Gateway WAF |
|--------|---------------------------|-------------------------|
| **Architecture** | User → Firewall → Synapse (direct) | User → App Gateway (proxy) → Synapse |
| **TLS Handling** | Requires TLS inspection/termination | App Gateway terminates SSL naturally |
| **Certificate Management** | Need trusted CA cert on clients | Standard SSL cert on App Gateway |
| **DNS Requirements** | Uses actual Synapse FQDN | Requires DNS override to App Gateway |
| **Rule Type** | Application rules with terminate_tls | WAF custom rules (native URL filtering) |
| **Traffic Pattern** | All traffic routed through firewall | Only Synapse traffic goes through App Gateway |
| **Complexity** | High (TLS inspection setup) | Medium (reverse proxy setup) |
| **Cost** | Firewall Premium ~$1.25/hr | App Gateway WAF_v2 ~$0.50/hr |

## Prerequisites

- Azure subscription with permissions to create resources
- Azure CLI or PowerShell installed
- Terraform >= 1.0

## Cost Warning

This POC deploys:
- Application Gateway WAF_v2 (~$0.50/hour)
- Synapse workspace (~$0.00/hour when paused)
- Synapse Spark pool (~$0.18/hour when running, auto-pauses after 15 min)
- Windows 10 VM (~$0.20/hour)
- Storage account and networking (minimal cost)

**Estimated cost: ~$0.70-1.00/hour or $17-24/day**

⚠️ **Remember to destroy resources after testing!**

## Deployment Steps

### 1. Navigate to POC Directory

```powershell
cd c:\Users\INLJLAA\Downloads\infra\appgw-waf-test-poc\terraform
```

### 2. Create terraform.tfvars File

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your passwords
```

Update the following in `terraform.tfvars`:
```hcl
admin_password             = "YourStrongPassword123!"
synapse_sql_admin_password = "YourSynapsePassword456!"
```

### 3. Initialize Terraform

```powershell
terraform init
```

### 4. Review Deployment Plan

```powershell
terraform plan
```

### 5. Deploy Resources

```powershell
terraform apply
```

Type `yes` when prompted. Deployment takes approximately **15-20 minutes**.

### 6. Save Outputs

```powershell
terraform output
```

Save the Application Gateway public IP and Synapse FQDN for testing.

## Testing Steps

### Step 1: Connect to Test VM

1. Open Azure Portal → Resource Group → Find VM `vm-test-user`
2. Connect via **Bastion** or configure RDP
3. Login with credentials from `terraform.tfvars`

### Step 2: Configure DNS Override (Critical)

The test VM needs to resolve Synapse FQDN to the Application Gateway IP.

**On the Test VM, open PowerShell as Administrator:**

```powershell
# Get values from terraform output
$appGatewayIP = "x.x.x.x"  # From terraform output
$synapseFQDN = "synapse-test-xxxxxxxx.dev.azuresynapse.net"  # From terraform output

# Add to hosts file
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "$appGatewayIP  $synapseFQDN"

# Verify
Get-Content C:\Windows\System32\drivers\etc\hosts
```

### Step 3: Test Access Patterns

**Test 1: General Synapse Access (Should Work)**
```powershell
curl https://synapse-test-xxxxxxxx.dev.azuresynapse.net/ -UseBasicParsing
```
**Expected Result:** 200 OK or 302 redirect to login

**Test 2: Spark History Server (Should Be BLOCKED)**
```powershell
curl https://synapse-test-xxxxxxxx.dev.azuresynapse.net/sparkhistory/ -UseBasicParsing
```
**Expected Result:** 403 Forbidden (blocked by WAF custom rule "BlockSparkHistoryServer")

**Test 3: Spark Monitoring (Should Be BLOCKED)**
```powershell
curl https://synapse-test-xxxxxxxx.dev.azuresynapse.net/monitoring/workloadTypes/spark/ -UseBasicParsing
```
**Expected Result:** 403 Forbidden (blocked by WAF custom rule "BlockSparkMonitoring")

**Test 4: Other Synapse Paths (Should Work)**
```powershell
# Test SQL endpoint
curl https://synapse-test-xxxxxxxx.dev.azuresynapse.net/sql/ -UseBasicParsing

# Test monitoring (non-spark)
curl https://synapse-test-xxxxxxxx.dev.azuresynapse.net/monitoring/ -UseBasicParsing
```
**Expected Result:** Various responses (200, 302, 401) - but NOT 403

### Step 4: Test via Browser

1. On test VM, open browser
2. Navigate to: `https://synapse-test-xxxxxxxx.dev.azuresynapse.net`
3. You should reach Synapse Studio login
4. Try to access Spark monitoring - should be blocked with 403 error

### Step 5: Verify WAF Logs

**In Azure Portal:**

1. Navigate to Application Gateway → **Logs**
2. Run this KQL query:

```kql
AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| where TimeGenerated > ago(1h)
| project TimeGenerated, requestUri_s, action_s, Message, clientIp_s
| order by TimeGenerated desc
```

**You should see:**
- ✅ `action_s = "Blocked"` for requests to `/sparkhistory/`
- ✅ `action_s = "Blocked"` for requests to `/monitoring/workloadTypes/spark/`
- ✅ `action_s = "Allowed"` or `action_s = "Detected"` for other paths

### Step 6: Test Spark Job (Optional)

If you want to test with actual Spark jobs:

1. Login to Synapse Studio via browser on test VM
2. Create a new Spark notebook
3. Run a simple Spark job:
   ```python
   print("Testing Spark")
   spark.range(100).count()
   ```
4. Try to access Spark History or Monitoring tabs - should be blocked

## Troubleshooting

### Issue: Cannot resolve Synapse FQDN

**Solution:** Verify hosts file entry is correct. Check with:
```powershell
Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String "synapse"
```

### Issue: Getting SSL certificate errors

**Solution:** The self-signed certificate is expected for testing. In browser, accept the certificate warning. For curl, use `-k` or `-SkipCertificateCheck`:
```powershell
curl https://synapse-xxx.dev.azuresynapse.net/ -SkipCertificateCheck
```

### Issue: All requests returning 403

**Solution:** 
1. Check WAF policy is in "Prevention" mode (not "Detection")
2. Verify Application Gateway backend pool health
3. Check private endpoint connections are "Approved"

### Issue: Requests timing out

**Solution:**
1. Verify Application Gateway health probe is passing
2. Check NSG rules allow traffic from VM subnet to App Gateway subnet
3. Verify private DNS zones are linked to VNet

## How It Works

### WAF Custom Rules

Two custom rules are configured in the WAF policy:

**Rule 1: BlockSparkHistoryServer (Priority 1)**
```hcl
Match Condition: RequestUri contains "/sparkhistory/"
Action: Block
```

**Rule 2: BlockSparkMonitoring (Priority 2)**
```hcl
Match Condition: RequestUri contains "/monitoring/workloadTypes/spark/"
Action: Block
```

### Traffic Flow

1. User VM resolves Synapse FQDN to Application Gateway IP (via hosts file)
2. Request goes to Application Gateway port 443
3. Application Gateway terminates SSL connection
4. WAF evaluates request against custom rules
   - If URI contains blocked paths → **403 Forbidden**
   - Otherwise → Continue to backend
5. Application Gateway forwards request to Synapse private endpoint via HTTPS
6. Synapse processes request and returns response
7. Application Gateway returns response to user

### Why Hosts File?

In production, you would:
- Use internal DNS to resolve Synapse FQDN to Application Gateway private IP
- Or use Azure Private DNS zones with custom A records
- Or use a custom domain name for the proxy

For this POC, hosts file is simplest for testing.

## Adapting for Production

### DNS Configuration

Instead of hosts file, configure DNS:

**Option 1: Override in Private DNS Zone**
```hcl
resource "azurerm_private_dns_a_record" "synapse_override" {
  name                = "synapse-test-xxxxxxxx"
  zone_name           = azurerm_private_dns_zone.synapse_dev.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_application_gateway.main.private_ip_address]
}
```

**Option 2: Use Custom Domain**
- Configure custom domain for Synapse access
- Point custom domain to Application Gateway
- Update WAF rules and backend pool accordingly

### Scaling

For production:
- Increase Application Gateway capacity or enable autoscaling
- Use production SSL certificate (not self-signed)
- Configure WAF with OWASP rule sets for additional security
- Enable Application Gateway diagnostics and monitoring
- Consider Application Gateway v2 features like URL rewrite

### Security Enhancements

1. **Restrict Application Gateway access**
   - Use NSG to limit source IPs to corporate network ranges
   - Configure Application Gateway to only accept traffic from specific subnets

2. **Enhanced WAF rules**
   - Add IP-based restrictions
   - Configure rate limiting
   - Enable bot protection
   - Use geo-filtering if applicable

3. **Certificate management**
   - Use Azure Key Vault integration (already configured)
   - Implement certificate rotation
   - Use CA-signed certificates

4. **Monitoring and alerts**
   - Configure alerts for WAF blocks
   - Monitor Application Gateway health
   - Track backend response times

## Comparison with Your Production Environment

### What's Different from PPD

- **Anonymized naming**: Uses generic names (`rg-appgw-waf-test-poc`, `vnet-appgw-test`)
- **Simplified network**: Single VNet instead of hub-spoke with transit
- **No firewall**: This approach replaces firewall with Application Gateway
- **Simplified routing**: Direct routing instead of complex route tables
- **Test certificates**: Self-signed certs instead of corporate CA

### What's the Same

- **Private endpoints**: Synapse has no public access
- **URL-based blocking**: Blocks same paths (`/sparkhistory/`, `/monitoring/workloadTypes/spark/`)
- **User experience**: Users access Synapse normally except blocked paths return 403
- **WAF in Prevention mode**: Actually blocks traffic (not just detects)

## Pros and Cons vs Firewall Approach

### Pros (Application Gateway WAF)

✅ **Simpler SSL handling** - No TLS inspection configuration needed
✅ **Lower cost** - App Gateway WAF_v2 cheaper than Firewall Premium  
✅ **Native URL filtering** - WAF designed for Layer 7 filtering
✅ **Additional security** - OWASP rule sets, bot protection, DDoS protection
✅ **Reverse proxy benefits** - Load balancing, SSL offload, URL rewrite

### Cons (Application Gateway WAF)

❌ **DNS complexity** - Requires DNS override or custom domain
❌ **Single point** - All Synapse traffic must go through App Gateway
❌ **Routing changes** - Users must route to App Gateway, not directly to Synapse
❌ **Limited scope** - Only works for HTTP/HTTPS traffic

### Which Approach to Choose?

**Use Application Gateway WAF if:**
- You can control DNS resolution for users
- You want reverse proxy capabilities
- You only need to filter HTTP/HTTPS traffic
- You want lower cost and simpler SSL management

**Use Firewall with TLS Inspection if:**
- You already have firewall in place for all traffic
- You need to inspect/filter non-HTTP protocols
- You can't modify DNS resolution
- You want consistent security policy across all traffic types

## Files in This POC

- `provider.tf` - Terraform and Azure provider configuration
- `variables.tf` - Input variables
- `network.tf` - VNet, subnets, NSGs, private DNS zones
- `appgw.tf` - Application Gateway WAF v2 with custom rules
- `synapse.tf` - Synapse workspace, Spark pool, private endpoints
- `vm.tf` - Windows test VM
- `outputs.tf` - Deployment outputs and testing instructions
- `README.md` - This file

## Cleanup

**IMPORTANT:** Destroy resources to avoid ongoing charges:

```powershell
terraform destroy
```

Type `yes` when prompted.

Verify in Azure Portal that resource group is deleted.

## Next Steps

After validating this POC works:

1. **Evaluate vs Firewall approach** - Which fits your architecture better?
2. **Test with real users** - Validate user experience
3. **Plan DNS strategy** - How will you implement DNS override in production?
4. **Security review** - Review WAF rules and OWASP configuration
5. **Integration planning** - How to integrate with existing network architecture?

## Questions?

This POC demonstrates that Application Gateway WAF can effectively block specific URL paths while allowing general Synapse access, providing an alternative approach to Azure Firewall with TLS inspection.

Key benefits:
- ✅ Simpler SSL/TLS configuration
- ✅ Native Layer 7 filtering
- ✅ Lower cost
- ✅ Reverse proxy capabilities

Key tradeoffs:
- ⚠️ Requires DNS configuration
- ⚠️ Only suitable for HTTP/HTTPS traffic
- ⚠️ All traffic must route through proxy
