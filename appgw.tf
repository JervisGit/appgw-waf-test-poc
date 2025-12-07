# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# User Assigned Managed Identity for App Gateway
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Key Vault for SSL certificate
resource "azurerm_key_vault" "main" {
  name                       = "kv-appgw-${random_string.unique.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = [
      "Create",
      "Delete",
      "Get",
      "Import",
      "List",
      "Purge",
      "Update"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
  }

  # Access policy for App Gateway managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.appgw.principal_id

    certificate_permissions = [
      "Get",
      "List"
    ]

    secret_permissions = [
      "Get",
      "List"
    ]
  }
}

# Self-signed certificate for App Gateway (for testing only)
resource "azurerm_key_vault_certificate" "appgw_cert" {
  name         = "appgw-ssl-cert"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=synapse-proxy.local"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = ["synapse-proxy.local", "*.synapse-proxy.local"]
      }
    }
  }
}

# WAF Policy with custom rules to block Spark monitoring URLs
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "waf-appgw-test"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  # Custom rule to block Spark History Server access
  custom_rules {
    name      = "BlockSparkHistoryServer"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }

      operator           = "Contains"
      negation_condition = false
      match_values = [
        "/sparkhistory/",
        "/sparkhistory"
      ]
    }
  }

  # Custom rule to block Spark Monitoring endpoints
  custom_rules {
    name      = "BlockSparkMonitoring"
    priority  = 2
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }

      operator           = "Contains"
      negation_condition = false
      match_values = [
        "/monitoring/workloadTypes/spark/"
      ]
    }
  }
}

# Random string for unique names
resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

# Application Gateway with WAF v2
resource "azurerm_application_gateway" "main" {
  name                = "appgw-synapse-proxy"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  # Frontend configuration
  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Backend pool pointing to Synapse private endpoint
  backend_address_pool {
    name  = "synapse-backend-pool"
    fqdns = var.deploy_synapse ? [azurerm_synapse_workspace.main[0].connectivity_endpoints.dev] : []
  }

  # Backend HTTP settings
  backend_http_settings {
    name                                = "synapse-backend-https"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = "synapse-health-probe"
  }

  # Health probe
  probe {
    name                                      = "synapse-health-probe"
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399", "401"]
    }
  }

  # HTTPS Listener with SSL certificate
  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-ssl-cert"
  }

  # HTTP to HTTPS redirect listener
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  # SSL Certificate
  ssl_certificate {
    name                = "appgw-ssl-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.appgw_cert.secret_id
  }

  # Routing rule - HTTPS to backend
  request_routing_rule {
    name                       = "https-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "synapse-backend-pool"
    backend_http_settings_name = "synapse-backend-https"
    priority                   = 100
  }

  # Routing rule - HTTP redirect to HTTPS
  request_routing_rule {
    name               = "http-to-https-redirect"
    rule_type          = "Basic"
    http_listener_name = "http-listener"
    redirect_configuration_name = "http-to-https"
    priority           = 200
  }

  redirect_configuration {
    name                 = "http-to-https"
    redirect_type        = "Permanent"
    target_listener_name = "https-listener"
    include_path         = true
    include_query_string = true
  }

  # Associate WAF Policy
  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  # Managed Identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  depends_on = [
    azurerm_key_vault_certificate.appgw_cert
  ]
}

# Data source for current Azure client config
data "azurerm_client_config" "current" {}
