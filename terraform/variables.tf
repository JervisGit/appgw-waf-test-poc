variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-appgw-waf-test-poc"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Admin username for test VM"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Admin password for test VM (use strong password)"
  type        = string
  sensitive   = true
}

variable "deploy_synapse" {
  description = "Whether to deploy Synapse workspace (set to false to use existing)"
  type        = bool
  default     = true
}

variable "synapse_sql_admin_username" {
  description = "Synapse SQL admin username"
  type        = string
  default     = "sqladminuser"
}

variable "synapse_sql_admin_password" {
  description = "Synapse SQL admin password"
  type        = string
  sensitive   = true
}
