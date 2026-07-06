variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "uksouth"
}

variable "name_prefix" {
  type        = string
  description = "Short prefix used in resource names."
  default     = "sde-dev"
}

variable "vm_size" {
  type        = string
  description = "Session host VM size."
  default     = "Standard_D2s_v4"
}

variable "host_count" {
  type        = number
  description = "Number of session-host VMs to provision in the pool. These persist as VM objects; the scaling plan powers them on/off (deallocates) to match demand, so size for peak concurrency (~ceil(peak concurrent users / maximum_sessions_allowed)). Default 2 covers up to ~8 sessions (5 devs with headroom)."
  default     = 2
}

variable "admin_username" {
  type        = string
  description = "Local administrator username on the session host."
  default     = "sdeadmin"
}

variable "avd_user_object_id" {
  type        = string
  description = "Object ID of the Entra user/group to grant desktop + VM login access. Empty = skip (assign roles later in the portal)."
  default     = ""
}

variable "profile_share_quota_gb" {
  type        = number
  description = "Provisioned size (GiB) of the Premium file share holding FSLogix profile containers. Premium Files bills on this quota regardless of actual usage."
  default     = 100
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default = {
    project    = "scalable-dev-env"
    managed-by = "terraform"
    env        = "dev"
  }
}
