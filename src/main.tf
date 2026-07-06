resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/24"]
  tags                = var.tags
}

resource "azurerm_subnet" "hosts" {
  name                 = "snet-hosts"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.0.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

## AVD Control Plane

resource "azurerm_virtual_desktop_host_pool" "this" {
  name                     = "vdpool-${var.name_prefix}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.this.name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 4
  start_vm_on_connect      = true
  validate_environment     = false
  tags                     = var.tags

  # Required to sign in to Entra-joined session hosts from non-Entra-joined
  # clients (e.g. the web client on Linux). Enables Entra ID auth over RDP.
  custom_rdp_properties = "enablerdsaadauth:i:1;targetisaadjoined:i:1;"
}

# Registration token the session host uses to join the pool. AVD requires the
# expiry to be 1 hour-30 days out; the token is regenerated when this rotates.
resource "time_rotating" "token" {
  rotation_days = 25
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = time_rotating.token.rotation_rfc3339
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = "vdag-${var.name_prefix}-desktop"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.this.id
  friendly_name       = "Development Environment Desktop"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace" "this" {
  name                = "vdws-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  friendly_name       = "Development Environment POC"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

# Desktop Virtualization User = allows user to see & launch the desktop
resource "azurerm_role_assignment" "desktop_user" {
  count                = var.avd_user_object_id == "" ? 0 : 1
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.avd_user_object_id
}

# Virtual Machine User Login = authorises logon to Entra-joined VM
resource "azurerm_role_assignment" "vm_login" {
  count                = var.avd_user_object_id == "" ? 0 : 1
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_user_object_id
}

## Storage

# Prevents duplicate Storage Account naming
resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "profiles" {
  name                     = "st${replace(var.name_prefix, "-", "")}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  account_tier             = "Premium"
  account_kind             = "FileStorage"
  account_replication_type = "LRS"
  tags                     = var.tags

  azure_files_authentication {
    directory_type = "AADKERB"
  }

  # Prevents public access without needing to configure Private Endpoint
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.hosts.id]
  }
}

resource "azurerm_storage_share" "profiles" {
  name               = "fslogix-profiles"
  storage_account_id = azurerm_storage_account.profiles.id
  quota              = var.profile_share_quota_gb
  enabled_protocol   = "SMB"
}

# Grants the AVD user(s) r/w/delete on the share over SMB; NTFS permissions
# on individual profile directories still apply
resource "azurerm_role_assignment" "profile_share_user" {
  count                = var.avd_user_object_id == "" ? 0 : 1
  scope                = azurerm_storage_share.profiles.rbac_scope_id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.avd_user_object_id
}

## Session Host

resource "random_password" "admin" {
  length      = 24
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# One NIC + VM + extension set per host. count (not for_each) because the pool
# is homogeneous and to allow for scaling via host_count
resource "azurerm_network_interface" "host" {
  count               = var.host_count
  name                = "nic-${var.name_prefix}-${format("%02d", count.index + 1)}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hosts.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "host" {
  count               = var.host_count
  name                = "vm-sde-${format("%02d", count.index + 1)}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = random_password.admin.result
  provision_vm_agent  = true
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.host[count.index].id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-23h2-avd"
    version   = "latest"
  }
}

# Entra ID join
resource "azurerm_virtual_machine_extension" "aad_login" {
  count                      = var.host_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
}

# Install AVD agent and register host with pool.
resource "azurerm_virtual_machine_extension" "avd_register" {
  count                      = var.host_count
  name                       = "AddSessionHost"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.83"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.aad_login]

  settings = jsonencode({
    modulesUrl            = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02790.438.zip"
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      hostPoolName = azurerm_virtual_desktop_host_pool.this.name
      aadJoin      = true
    }
  })

  protected_settings = jsonencode({
    properties = {
      registrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.this.token
    }
  })
}

# Configure FSLogix profile persistence and install dev tools in a
# single CustomScriptExtension.
#
# Windows allows only one per VM per handler. Runs after Entra join
# + AVD registration
resource "azurerm_virtual_machine_extension" "configure_host" {
  count                      = var.host_count
  name                       = "ConfigureHost"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on = [
    azurerm_virtual_machine_extension.aad_login,
    azurerm_virtual_machine_extension.avd_register,
  ]

  settings = jsonencode({
    commandToExecute = "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(templatefile("${path.module}/configure-host.ps1.tftpl", {
      vhd_location = "\\\\${azurerm_storage_account.profiles.name}.file.core.windows.net\\${azurerm_storage_share.profiles.name}"
    }), "UTF-16LE")}"
  })
}

## Autoscaling

# "Azure Virtual Desktop" service principal
data "azuread_service_principal" "avd" {
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07"
}

# Allow AVD service to start & deallocate SHs
resource "azurerm_role_assignment" "avd_power" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  principal_id         = data.azuread_service_principal.avd.object_id
}

resource "azurerm_virtual_desktop_scaling_plan" "this" {
  name                = "vdscaling-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  friendly_name       = "Development Environment Autoscale"
  time_zone           = "GMT Standard Time" # Windows tz id; tracks GMT/BST automatically
  tags                = var.tags

  schedule {
    name         = "Weekdays"
    days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    # Example working hours are 7AM-8:30PM, with most users
    # logging in between 8:30AM-6PM

    ramp_up_start_time                 = "06:30"
    ramp_up_load_balancing_algorithm   = "BreadthFirst"
    ramp_up_minimum_hosts_percent      = 50
    ramp_up_capacity_threshold_percent = 60

    # BreadthFirst spreads users across hosts for more responsive sessions
    peak_start_time               = "08:00"
    peak_load_balancing_algorithm = "BreadthFirst"

    # No forced logoff, only empty SHs are deallocated
    ramp_down_start_time                 = "18:00"
    ramp_down_load_balancing_algorithm   = "DepthFirst"
    ramp_down_minimum_hosts_percent      = 0
    ramp_down_force_logoff_users         = false
    ramp_down_wait_time_minutes          = 30
    ramp_down_notification_message       = "This host is winding down. Please save your work."
    ramp_down_capacity_threshold_percent = 90
    ramp_down_stop_hosts_when            = "ZeroSessions"

    # Scale to zero. start_vm_on_connect wakes host(s) on-demand
    off_peak_start_time               = "20:30"
    off_peak_load_balancing_algorithm = "DepthFirst"
  }

  host_pool {
    hostpool_id          = azurerm_virtual_desktop_host_pool.this.id
    scaling_plan_enabled = true
  }

  depends_on = [azurerm_role_assignment.avd_power]
}
