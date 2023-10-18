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

output "resource_group_name" {
  value = data.azurerm_resource_group.resource_group.name
}

## AKS Cluster
resource "azurerm_kubernetes_cluster" "aks-cluster" {
  name                = "${var.demo_name}-aks-cluster"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
  dns_prefix          = "${var.demo_name}"
  default_node_pool {
    name       = "default"
    node_count = 1 
    vm_size    = "Standard_B4ms"
  }
  identity {
    type = "SystemAssigned"
  }
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.aks-cluster.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.aks-cluster.kube_config_raw
  sensitive = true
}

output "kubernetes_cluster_id" {
  value = azurerm_kubernetes_cluster.aks-cluster.id
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.aks-cluster.name
}

## Public IP
# When defining a static IP address with a domain name label, Azure automatically allocates an IP and associates it with an auto-generated DNS name (I might need a CNAME to avoid the issue of the hostname changing)
resource "azurerm_public_ip" "aks-public-ip" {
  name                = "${var.demo_name}-public-ip"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_kubernetes_cluster.aks-cluster.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  domain_name_label   = "${var.domain_name_label}" 
}

output "public_ip_address" {
  value = azurerm_public_ip.aks-public-ip.ip_address
}

# If you need a CNAME record uncomment this 
## DNS A Record
#resource "azurerm_dns_a_record" "dns-record" {
#  name                = "${var.demo_name}-dns-record"
#  zone_name           = azurerm_dns_zone.dns-zone.name
#  resource_group_name = data.azurerm_resource_group.resource_group.name
#  ttl                 = 300
#  target_resource_id  = azurerm_public_ip.public-ip.id
#}

# Write kubeconfig to local file
resource "local_sensitive_file" "kubeconfig" {
    content     = azurerm_kubernetes_cluster.aks-cluster.kube_config_raw
    filename    = "./kubeconfig.json"
    depends_on = [azurerm_kubernetes_cluster.aks-cluster]
}

## Install ingress-nginx controller via helm
provider "helm" {
  kubernetes {
    config_path = "./kubeconfig.json"
  }
}

resource "helm_release" "ingress-nginx" {
  name       = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace  = true
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  wait       = false
  depends_on = [local_sensitive_file.kubeconfig]

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.aks-public-ip.ip_address 
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-dns-label-name" 
    value = "${var.domain_name_label}"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path" 
    value = "/healthz"
  }
}



