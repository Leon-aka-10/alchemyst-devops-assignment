resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  vms = {
    gateway = {
      subnet = azurerm_subnet.public.id
      nsg    = azurerm_network_security_group.gateway_nsg.id
      size   = var.vm_size_gateway
      disk   = 30
    }
    inference = {
      subnet = azurerm_subnet.private.id
      nsg    = azurerm_network_security_group.worker_nsg.id
      size   = var.vm_size_inference
      disk   = 40
    }
    caller = {
      subnet = azurerm_subnet.private.id
      nsg    = azurerm_network_security_group.worker_nsg.id
      size   = var.vm_size_caller
      disk   = 30
    }
  }
}

resource "azurerm_network_interface" "nic" {
  for_each            = local.vms
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = (
      each.key == "gateway"
      ? azurerm_public_ip.gateway_ip.id
      : null
    )
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each                  = local.vms
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = each.value.nsg
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each            = local.vms
  name                = "${each.key}-vm-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = each.value.size
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.nic[each.key].id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = each.value.disk
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Student account note: no zone specification
  # francecentral does not guarantee zone availability on student subscriptions
}