output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "application_gateway_public_ip" {
  description = "Public IP of Application Gateway (use this to access Synapse)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "synapse_workspace_name" {
  description = "Synapse workspace name"
  value       = var.deploy_synapse ? azurerm_synapse_workspace.main[0].name : "Not deployed - using existing"
}

output "synapse_dev_endpoint" {
  description = "Synapse dev endpoint (private)"
  value       = var.deploy_synapse ? azurerm_synapse_workspace.main[0].connectivity_endpoints.dev : "N/A"
}

output "synapse_spark_pool_name" {
  description = "Synapse Spark pool name"
  value       = var.deploy_synapse ? azurerm_synapse_spark_pool.main[0].name : "Not deployed"
}

output "test_vm_name" {
  description = "Test VM name"
  value       = azurerm_windows_virtual_machine.testvm.name
}

output "test_vm_private_ip" {
  description = "Test VM private IP"
  value       = azurerm_network_interface.testvm.private_ip_address
}

output "waf_policy_name" {
  description = "WAF Policy name"
  value       = azurerm_web_application_firewall_policy.main.name
}

output "setup_command" {
  description = "Command to run on test VM to configure certificate and hosts file"
  value       = <<-EOT
Run this on the test VM (as Administrator):

cd C:\
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JervisGit/appgw-waf-test-poc/master/scripts/setup-vm.ps1" -OutFile setup-vm.ps1
.\setup-vm.ps1 -KeyVaultName "${azurerm_key_vault.main.name}" -CertificateName "${azurerm_key_vault_certificate.appgw_cert.name}" -AppGatewayIP "${azurerm_public_ip.appgw.ip_address}" -SynapseFQDN "${var.deploy_synapse ? split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2] : "synapse-placeholder.dev.azuresynapse.net"}"
EOT
}

output "instructions" {
  description = "Testing instructions"
  value       = <<-EOT
  
  ========================================
  APPLICATION GATEWAY WAF POC - DEPLOYMENT COMPLETE
  ========================================
  
  ## Architecture
  Test VM (Users) → Application Gateway (WAF) → Synapse (Private Endpoint)
  
  ## Access Information
  - Application Gateway Public IP: ${azurerm_public_ip.appgw.ip_address}
  - Test VM: ${azurerm_windows_virtual_machine.testvm.name}
  - Test VM Private IP: ${azurerm_network_interface.testvm.private_ip_address}
  - Key Vault: ${azurerm_key_vault.main.name}
  ${var.deploy_synapse ? "- Synapse Workspace: ${azurerm_synapse_workspace.main[0].name}" : ""}
  ${var.deploy_synapse ? "- Spark Pool: ${azurerm_synapse_spark_pool.main[0].name}" : ""}
  
  ## IMPORTANT: Setup Certificate & Hosts File on Test VM
  
  To test in browser without certificate warnings, run this automated setup:
  
  1. Connect to Test VM (${azurerm_windows_virtual_machine.testvm.name}) via Bastion/RDP
  2. Login with Azure CLI: az login
  3. Run the setup script (see 'terraform output setup_command')
  
  The script will:
  - Download certificate from Key Vault
  - Install it as Trusted Root CA (no browser warnings!)
  - Configure hosts file to resolve Synapse FQDN to App Gateway
  
  ## Manual Setup (Alternative)
  
  If automated script doesn't work, manually add to C:\Windows\System32\drivers\etc\hosts:
  
  ${azurerm_public_ip.appgw.ip_address}  ${var.deploy_synapse ? split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2] : "your-synapse-workspace.dev.azuresynapse.net"}
  
  Note: Without certificate installation, browser will show warnings (can click through).
  
  ## Testing Steps
  
  1. Connect to Test VM:
     - Use Azure Bastion or RDP
     - Username: ${var.admin_username}
  
  2. Update hosts file (as Administrator):
     PowerShell:
     Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "${azurerm_public_ip.appgw.ip_address}  ${var.deploy_synapse ? split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2] : "synapse-workspace.dev.azuresynapse.net"}"
  
  3. Test General Synapse Access (should work):
     ${var.deploy_synapse ? "curl https://${split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2]}/" : "curl https://your-synapse-workspace.dev.azuresynapse.net/"}
     Expected: 200 OK or redirect to login
  
  4. Test Spark History Access (should be BLOCKED by WAF):
     ${var.deploy_synapse ? "curl https://${split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2]}/sparkhistory/" : "curl https://your-synapse-workspace.dev.azuresynapse.net/sparkhistory/"}
     Expected: 403 Forbidden (blocked by WAF custom rule)
  
  5. Test Spark Monitoring Access (should be BLOCKED by WAF):
     ${var.deploy_synapse ? "curl https://${split("/", azurerm_synapse_workspace.main[0].connectivity_endpoints.dev)[2]}/monitoring/workloadTypes/spark/" : "curl https://your-synapse-workspace.dev.azuresynapse.net/monitoring/workloadTypes/spark/"}
     Expected: 403 Forbidden (blocked by WAF custom rule)
  
  ## Key Differences from Firewall Approach
  
  - ✅ Users access Synapse through Application Gateway (reverse proxy)
  - ✅ WAF blocks at Layer 7 based on URL paths
  - ✅ No TLS inspection needed (App Gateway terminates SSL)
  - ✅ Private endpoints keep Synapse fully private
  - ✅ Simpler than firewall + TLS inspection
  - ⚠️ Requires DNS resolution to point to App Gateway
  - ⚠️ All Synapse traffic must go through App Gateway
  
  ## Verify WAF Blocking in Azure Portal
  
  1. Navigate to Application Gateway → Logs
  2. Run this query:
  
  AzureDiagnostics
  | where ResourceType == "APPLICATIONGATEWAYS"
  | where Category == "ApplicationGatewayFirewallLog"
  | where TimeGenerated > ago(1h)
  | project TimeGenerated, requestUri_s, action_s, Message
  | order by TimeGenerated desc
  
  You should see "Block" actions for /sparkhistory/ and /monitoring/workloadTypes/spark/ paths.
  
  EOT
}
