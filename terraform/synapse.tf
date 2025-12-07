# Storage Account for Synapse
resource "azurerm_storage_account" "synapse" {
  count = var.deploy_synapse ? 1 : 0

  name                     = "stsynapse${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Data Lake Gen2

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    
    # Allow from VNet subnets
    virtual_network_subnet_ids = [
      azurerm_subnet.synapse_pe.id,
      azurerm_subnet.vm.id,
      azurerm_subnet.appgw.id
    ]
  }
}

# Storage Container for Synapse
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  count = var.deploy_synapse ? 1 : 0

  name               = "synapsefilesystem"
  storage_account_id = azurerm_storage_account.synapse[0].id
}

# Synapse Workspace with Managed VNet
resource "azurerm_synapse_workspace" "main" {
  count = var.deploy_synapse ? 1 : 0

  name                                 = "synapse-test-${random_string.unique.result}"
  resource_group_name                  = azurerm_resource_group.main.name
  location                             = azurerm_resource_group.main.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse[0].id
  sql_administrator_login              = var.synapse_sql_admin_username
  sql_administrator_login_password     = var.synapse_sql_admin_password
  managed_virtual_network_enabled      = true
  public_network_access_enabled        = false

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Test"
    Purpose     = "WAF-POC"
  }
}

# Synapse Firewall Rule - Allow Azure Services
resource "azurerm_synapse_firewall_rule" "allow_azure_services" {
  count = var.deploy_synapse ? 1 : 0

  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.main[0].id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Synapse Spark Pool
resource "azurerm_synapse_spark_pool" "main" {
  count = var.deploy_synapse ? 1 : 0

  name                 = "sparkpool01"
  synapse_workspace_id = azurerm_synapse_workspace.main[0].id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"
  node_count           = 3

  auto_scale {
    max_node_count = 10
    min_node_count = 3
  }

  auto_pause {
    delay_in_minutes = 15
  }

  spark_version = "3.3"

  tags = {
    Environment = "Test"
  }
}

# Private Endpoint for Synapse Dev endpoint
resource "azurerm_private_endpoint" "synapse_dev" {
  count = var.deploy_synapse ? 1 : 0

  name                = "pe-synapse-dev"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.synapse_pe.id

  private_service_connection {
    name                           = "synapse-dev-privateserviceconnection"
    private_connection_resource_id = azurerm_synapse_workspace.main[0].id
    is_manual_connection           = false
    subresource_names              = ["dev"]
  }

  private_dns_zone_group {
    name                 = "synapse-dev-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.synapse_dev.id]
  }
}

# Private Endpoint for Synapse SQL
resource "azurerm_private_endpoint" "synapse_sql" {
  count = var.deploy_synapse ? 1 : 0

  name                = "pe-synapse-sql"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.synapse_pe.id

  private_service_connection {
    name                           = "synapse-sql-privateserviceconnection"
    private_connection_resource_id = azurerm_synapse_workspace.main[0].id
    is_manual_connection           = false
    subresource_names              = ["sql"]
  }

  private_dns_zone_group {
    name                 = "synapse-sql-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.synapse_sql.id]
  }
}

# Grant Storage Blob Data Contributor to Synapse MI
resource "azurerm_role_assignment" "synapse_storage" {
  count = var.deploy_synapse ? 1 : 0

  scope                = azurerm_storage_account.synapse[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main[0].identity[0].principal_id
}
