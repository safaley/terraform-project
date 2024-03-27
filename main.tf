terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.91.0"
    }
  }

}


provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "terra-rg" {
  name     = "terra-resources"
  location = "East US"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "terra-vn" {
  name                = "terra-network"
  resource_group_name = azurerm_resource_group.terra-rg.name
  location            = azurerm_resource_group.terra-rg.location
  address_space       = ["10.123.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "terra-subnet" {
  name                 = "terra-subnet"
  resource_group_name  = azurerm_resource_group.terra-rg.name
  virtual_network_name = azurerm_virtual_network.terra-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "terra-sg" {
  name                = "terra-sg"
  location            = azurerm_resource_group.terra-rg.location
  resource_group_name = azurerm_resource_group.terra-rg.name
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "terra-dev-rule" {
  name                        = "terra-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.terra-rg.name
  network_security_group_name = azurerm_network_security_group.terra-sg.name
}

resource "azurerm_subnet_network_security_group_association" "terra-sga" {
  subnet_id                 = azurerm_subnet.terra-subnet.id
  network_security_group_id = azurerm_network_security_group.terra-sg.id
}

resource "azurerm_public_ip" "terra-ip" {
  name                = "terra-ip"
  resource_group_name = azurerm_resource_group.terra-rg.name
  location            = azurerm_resource_group.terra-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "terra-nic" {
  name                = "terra-nic"
  location            = azurerm_resource_group.terra-rg.location
  resource_group_name = azurerm_resource_group.terra-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.terra-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.terra-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "terra-vm" {
  name                = "terra-vm"
  resource_group_name = azurerm_resource_group.terra-rg.name
  location            = azurerm_resource_group.terra-rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.terra-nic.id,
  ]

  custom_data = filebase64("customdata.tpl")
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/terraazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/terraazurekey",
    })
    interpreter = var.host_os == "mac" ?["bash", "-c"] : ["Powershell", "-Command"]
  }
}

data "azurerm_public_ip" "terra-ip-data" {
  name = azurerm_public_ip.terra-ip.name
  resource_group_name = azurerm_resource_group.terra-rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.terra-vm.name}: ${data.azurerm_public_ip.terra-ip-data.ip_address}"
}