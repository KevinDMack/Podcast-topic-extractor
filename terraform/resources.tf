# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Storage Account for Function App and Blob Storage
resource "azurerm_storage_account" "main" {
  name                     = substr("podcastsa${var.environment}${random_string.suffix.result}", 0, 24)
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  blob_properties {
    versioning_enabled = true
  }
  
  tags = var.tags
}

# Blob Container for podcast episodes and keywords
resource "azurerm_storage_container" "podcast_episodes" {
  name                  = "podcast-episodes"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "podcast-asp-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan
  
  tags = var.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "podcast-ai-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  
  tags = var.tags
}

# Cognitive Services - Text Analytics
resource "azurerm_cognitive_account" "text_analytics" {
  name                = "podcast-textanalytics-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "TextAnalytics"
  sku_name            = "S0"
  
  tags = var.tags
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "podcast-kv-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  tags = var.tags
}

# Key Vault Access Policy for Terraform deployment principal
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "spotify_client_id" {
  name         = "spotify-client-id"
  value        = var.spotify_client_id
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}

resource "azurerm_key_vault_secret" "spotify_client_secret" {
  name         = "spotify-client-secret"
  value        = var.spotify_client_secret
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}

resource "azurerm_key_vault_secret" "text_analytics_key" {
  name         = "text-analytics-key"
  value        = azurerm_cognitive_account.text_analytics.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Linux Function App
resource "azurerm_linux_function_app" "main" {
  name                = "podcast-func-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "SPOTIFY_CLIENT_ID"              = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.spotify_client_id.id})"
    "SPOTIFY_CLIENT_SECRET"          = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.spotify_client_secret.id})"
    "TEXT_ANALYTICS_ENDPOINT"        = azurerm_cognitive_account.text_analytics.endpoint
    "TEXT_ANALYTICS_KEY"             = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.text_analytics_key.id})"
    "BLOB_STORAGE_ACCOUNT_URL"       = azurerm_storage_account.main.primary_blob_endpoint
    "BLOB_CONTAINER_NAME"            = azurerm_storage_container.podcast_episodes.name
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
  }
  
  tags = var.tags
}

# Key Vault Access Policy for Function App
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Role Assignment: Storage Blob Data Contributor for Function App
resource "azurerm_role_assignment" "function_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: Cognitive Services User for Function App
resource "azurerm_role_assignment" "function_cognitive_services_user" {
  scope                = azurerm_cognitive_account.text_analytics.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
