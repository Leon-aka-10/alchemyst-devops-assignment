output "gateway_public_ip" {
  description = "Public IP of the API gateway"
  value       = azurerm_public_ip.gateway_ip.ip_address
}

output "engine_private_ip" {
  description = "Private IP of iii engine VM"
  value       = azurerm_network_interface.nic["engine"].private_ip_address
}

output "inference_private_ip" {
  description = "Private IP of inference worker VM"
  value       = azurerm_network_interface.nic["inference"].private_ip_address
}

output "caller_private_ip" {
  description = "Private IP of caller worker VM"
  value       = azurerm_network_interface.nic["caller"].private_ip_address
}

output "resource_group" {
  description = "Resource group — use this to verify teardown"
  value       = azurerm_resource_group.rg.name
}