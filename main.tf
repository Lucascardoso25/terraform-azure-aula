
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
}

# Chave publica gerada pelo GitHub Actions
variable "admin_ssh_public_key" {
  description = "Chave publica SSH temporaria do laboratorio"
  type        = string
  sensitive   = true
}

# ============================================================
# RESOURCE GROUP
# ============================================================

resource "azurerm_resource_group" "lab" {
  name     = "rg-terraform-aula"
  location = "southafricanorth"
}

# ============================================================
# REDE VIRTUAL E SUB-REDE
# ============================================================

resource "azurerm_virtual_network" "lab" {
  name                = "terraform-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.10.1.0/24"]
}

# ============================================================
# REGRAS DE SEGURANCA DA REDE
# ============================================================

resource "azurerm_network_security_group" "vm" {
  name                = "terraform-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "HTTP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
   
  security_rule {
    name                       = "SSH"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ============================================================
# IP PUBLICO
# ============================================================

resource "azurerm_public_ip" "vm" {
  name                = "terraform-ip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ============================================================
# INTERFACE DE REDE
# ============================================================

resource "azurerm_network_interface" "vm" {
  name                = "terraform-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# ============================================================
# MAQUINA VIRTUAL LINUX COM DOCKER
# ============================================================

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "terraform-linux-vm"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = "Standard_B2ats_v2"

  admin_username                  = "azureuser"
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.vm.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  custom_data = base64encode(<<-CLOUDCONFIG
    #cloud-config
    package_update: true
    packages:
      - docker.io
    runcmd:
      - [systemctl, enable, --now, docker]
      - [usermod, -aG, docker, azureuser]
  CLOUDCONFIG
  )

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# ============================================================
# INFORMACOES DA INFRAESTRUTURA CRIADA
# ============================================================

output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "nome_vm" {
  value = azurerm_linux_virtual_machine.vm.name
}

output "ip_publico" {
  value = azurerm_public_ip.vm.ip_address
}

output "tamanho_vm" {
  value = azurerm_linux_virtual_machine.vm.size
}
