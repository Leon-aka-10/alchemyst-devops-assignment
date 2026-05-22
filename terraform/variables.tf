variable "location" {
  description = "Azure region — student account restricted to francecentral"
  type        = string
  default     = "francecentral"
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
  default     = "rg-alchemyst-assignment"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  sensitive   = true
}

variable "admin_ip" {
  description = "Allowed IP for SSH restriction on gateway NSG"
  type        = string
  sensitive   = true
}

variable "vm_size_gateway" {
  description = "Gateway VM — also hosts iii engine. B1s within student quota."
  type        = string
  default     = "Standard_B1s"
}

variable "vm_size_inference" {
  description = "Inference VM — B2s minimum for Gemma model (8GB RAM)"
  type        = string
  default     = "Standard_B2s"
}

variable "vm_size_caller" {
  description = "Caller worker VM — B1s sufficient"
  type        = string
  default     = "Standard_B1s"
}