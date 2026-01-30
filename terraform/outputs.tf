output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "blob_container_name" {
  description = "Name of the Blob Container"
  value       = azurerm_storage_container.podcast_episodes.name
}

output "text_analytics_endpoint" {
  description = "Endpoint for Text Analytics service"
  value       = azurerm_cognitive_account.text_analytics.endpoint
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "resource_group_name" {
  description = "Name of the Resource Group"
  value       = azurerm_resource_group.main.name
}

output "get_podcast_episodes_url" {
  description = "URL for GetPodcastEpisodes function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/GetPodcastEpisodes"
}

output "extract_keywords_url" {
  description = "URL for ExtractKeywords function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/ExtractKeywords"
}
