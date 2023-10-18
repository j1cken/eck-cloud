terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Use an existing resource group
data "azurerm_resource_group" "resource_group" {
  name = "${var.azure_resource_group_name}" 
}

output "id" {
  value = data.azurerm_resource_group.resource_group.id
}

# Event-Hub Namespace
resource "azurerm_eventhub_namespace" "event-hub-namespace" {
  name                = "${var.demo_name}-event-hub-namespace"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
  sku                 = "Standard"
  capacity            = 1
}

# Event-Hub
resource "azurerm_eventhub" "event-hub" {
  name                = "${var.demo_name}-event-hub"
  namespace_name      = azurerm_eventhub_namespace.event-hub-namespace.name
  resource_group_name = data.azurerm_resource_group.resource_group.name
  partition_count     = 1 
  message_retention   = 1
}

## Authorization rule for EventHub
resource "azurerm_eventhub_namespace_authorization_rule" "event-hub-namespace-authorization-rule" {
  name                = "${var.demo_name}-event-hub-authorization-rule" 
  namespace_name      = azurerm_eventhub_namespace.event-hub-namespace.name
  resource_group_name = data.azurerm_resource_group.resource_group.name
  listen              = false 
  send                = true
  manage              = false
}

## Storage Account
resource "azurerm_storage_account" "storage-account" {
  name                     = "${var.storage_name}""
  resource_group_name      = data.azurerm_resource_group.resource_group.name
  location                 = data.azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

## Storage Container
resource "azurerm_storage_container" "storage-container" {
  name                  = "${var.demo_name}-container-for-agent"
  storage_account_name  = azurerm_storage_account.storage-account.name
  container_access_type = "private"
}
