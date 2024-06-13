# main.tf

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_secrets    = false
    }
  }
}

provider "azuread" {}

data "azurerm_client_config" "current" {}

# Resource group

resource "azurerm_resource_group" "RGvolny" {
  name     = "RG-volny"
  location = "West Europe"
}

# VNET

resource "azurerm_virtual_network" "volnyvnet" {
  name                = "vnet-volny"
  address_space       = ["12.12.0.0/16"]
  location            = azurerm_resource_group.RGvolny.location
  resource_group_name = azurerm_resource_group.RGvolny.name
}

# SUBNET1 - KeyVault

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.RGvolny.name
  virtual_network_name = azurerm_virtual_network.volnyvnet.name
  address_prefixes     = ["12.12.0.0/26"]
  service_endpoints = null

  depends_on = [ azurerm_virtual_network.volnyvnet ]

}

# SUBNET2 - PostgreSQL

resource "azurerm_subnet" "subnet2" {
  name                 = "subnet2"
  resource_group_name  = azurerm_resource_group.RGvolny.name
  virtual_network_name = azurerm_virtual_network.volnyvnet.name
  address_prefixes     = ["12.12.0.64/26"]
delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
  depends_on = [ azurerm_virtual_network.volnyvnet ]

}

# DNS ZONES
# PRIVATE ZONE1 - KeyVault
resource "azurerm_private_dns_zone" "zone1" {
  name                = "zone1.private"
  resource_group_name = azurerm_resource_group.RGvolny.name
}
# PRIVATE ZONE2 - PostgreSQL
resource "azurerm_private_dns_zone" "zone2" {
  name                = "zone2.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.RGvolny.name
}
# ZONE LINK 1
resource "azurerm_private_dns_zone_virtual_network_link" "zone1link" {
  name                  = "zone1Link"
  private_dns_zone_name = azurerm_private_dns_zone.zone1.name
  resource_group_name   = azurerm_resource_group.RGvolny.name
  virtual_network_id    = azurerm_virtual_network.volnyvnet.id
  depends_on = [ azurerm_virtual_network.volnyvnet ]
}
#ZONE LINK 2
resource "azurerm_private_dns_zone_virtual_network_link" "zone2link" {
  name                  = "zone2Link"
  private_dns_zone_name = azurerm_private_dns_zone.zone2.name
  resource_group_name   = azurerm_resource_group.RGvolny.name
  virtual_network_id    = azurerm_virtual_network.volnyvnet.id

 depends_on = [ azurerm_subnet_network_security_group_association.subnet2asoc ]
}
resource "azurerm_subnet_network_security_group_association" "subnet2asoc" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.volnynsg.id
}

# Public IP

resource "azurerm_public_ip" "volnypip" {
  name                = "volny-pip"
  location            = azurerm_resource_group.RGvolny.location
  resource_group_name = azurerm_resource_group.RGvolny.name
  allocation_method   = "Static"
}

# NIC

resource "azurerm_network_interface" "volnynic" {
  name                = "volny-nic"
  location            = azurerm_resource_group.RGvolny.location
  resource_group_name = azurerm_resource_group.RGvolny.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.volnypip.id
  }

  depends_on = [ azurerm_subnet.subnet1 ]
}

# NSG

resource "azurerm_network_security_group" "volnynsg" {
  name                = "volny-nsg"
  location            = azurerm_resource_group.RGvolny.location
  resource_group_name = azurerm_resource_group.RGvolny.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
}
 security_rule {
    name                       = "deny-all"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NSG association

resource "azurerm_network_interface_security_group_association" "volnynicnsg" {
  network_interface_id      = azurerm_network_interface.volnynic.id
  network_security_group_id = azurerm_network_security_group.volnynsg.id

  depends_on = [ azurerm_virtual_network.volnyvnet ]

}

# VM

resource "azurerm_windows_virtual_machine" "VolnyWINvm" {
  name                  = "VIRTUALKA1"
  location              = azurerm_resource_group.RGvolny.location
  resource_group_name   = azurerm_resource_group.RGvolny.name
  network_interface_ids = [azurerm_network_interface.volnynic.id]
  size                  = "Standard_D2s_v3"
  admin_username        = "volnyjan"
  admin_password        = "Password123"
  computer_name         = "VIRTUALKA1"

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_disk {
    name              = "example-os-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

identity {
    type = "SystemAssigned"
  }

depends_on = [ azurerm_network_interface.volnynic ]
}

# KEAVAULT

resource "azurerm_key_vault" "kvault000" {
  name                        = "kvault000"
  location                    = azurerm_resource_group.RGvolny.location
  resource_group_name         = azurerm_resource_group.RGvolny.name
  sku_name                    = "premium"
  tenant_id                   = "59f4bfff-76be-4144-ad87-688e9734098b"
  purge_protection_enabled    = true
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    ip_rules = []

  virtual_network_subnet_ids = [azurerm_subnet.subnet1.id]
  }
}


resource azurerm_key_vault_access_policy terraform_user {
  key_vault_id = azurerm_key_vault.kvault000.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_virtual_machine.VolnyWINvm.identity[0].principal_id
  
  key_permissions = [
    "Get",
    ]

  secret_permissions = [
    "Backup","Delete","Get","List","Purge","Recover","Restore", "Set"
  ]

}

# PostgreSQL

resource "azurerm_postgresql_flexible_server" "mypostgres001" {
  name                = "mypostgres001"
  resource_group_name = azurerm_resource_group.RGvolny.name
  location            = azurerm_resource_group.RGvolny.location
  version             = "13"
  administrator_login = "psqladmin"
  administrator_password = "Heslo123"
  sku_name            = "GP_Standard_D4s_v3"
  storage_mb          = 32768 # 32GB in MB
  zone                = "2"
  backup_retention_days = 7
  private_dns_zone_id = azurerm_private_dns_zone.zone2.id
  delegated_subnet_id = azurerm_subnet.subnet2.id
  public_network_access_enabled = false
  depends_on = [azurerm_private_dns_zone_virtual_network_link.zone2link]
  }

  # Output Key Vault URI
output "key_vault_uri" {
  value = azurerm_key_vault.kvault000.vault_uri
}

# Private Endpoint
resource "azurerm_private_endpoint" "kvprivate" {
  name                = "kvprivate"
  location            = azurerm_resource_group.RGvolny.location
  resource_group_name = azurerm_resource_group.RGvolny.name
  subnet_id           = azurerm_subnet.subnet2.id

  private_service_connection {
    name                           = "example-psc"
    private_connection_resource_id = azurerm_postgresql_flexible_server.mypostgres001.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }
}
# Private DNS Zone Record
resource "azurerm_private_dns_a_record" "kvrecord" {
  name                = azurerm_key_vault.kvault000.name
  zone_name           = azurerm_private_dns_zone.zone1.name
  resource_group_name = azurerm_resource_group.RGvolny.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.kvprivate.private_service_connection[0].private_ip_address]
}


