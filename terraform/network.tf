# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-appgw-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.200.0.0/16"]
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.200.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

# Subnet for Synapse Private Endpoints
resource "azurerm_subnet" "synapse_pe" {
  name                 = "snet-synapse-pe"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.200.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

# Subnet for Test VMs (user subnet)
resource "azurerm_subnet" "vm" {
  name                 = "snet-users"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.200.3.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

# Network Security Group for VM subnet
resource "azurerm_network_security_group" "vm" {
  name                = "nsg-users"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow outbound to Application Gateway
  security_rule {
    name                       = "AllowOutboundToAppGw"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "80"]
    source_address_prefix      = "10.200.3.0/24"
    destination_address_prefix = "10.200.1.0/24"
  }

  # Allow RDP for management (restrict to your IP in production)
  security_rule {
    name                       = "AllowRDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*" # Change to your IP for security
    destination_address_prefix = "*"
  }
}

# Associate NSG with VM subnet
resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# Private DNS Zone for Synapse
resource "azurerm_private_dns_zone" "synapse_dev" {
  name                = "privatelink.dev.azuresynapse.net"
  resource_group_name = azurerm_resource_group.main.name
}

# Link DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "synapse_dev" {
  name                  = "synapse-dev-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_dev.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# Private DNS Zone for Synapse SQL
resource "azurerm_private_dns_zone" "synapse_sql" {
  name                = "privatelink.sql.azuresynapse.net"
  resource_group_name = azurerm_resource_group.main.name
}

# Link DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "synapse_sql" {
  name                  = "synapse-sql-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_sql.name
  virtual_network_id    = azurerm_virtual_network.main.id
}
