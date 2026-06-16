variable "environment" {
  type        = string
  description = "Deployment environment (dev, test, prod)"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "layer" {
  type        = string
  description = "Medallion architecture layer (bronze, silver, gold)"
  validation {
    condition     = contains(["bronze", "silver", "gold"], var.layer)
    error_message = "Layer must be bronze, silver, or gold."
  }
}

variable "data_source" {
  type        = string
  description = "Optional data source name. When set, scopes the workspace to a single source, producing {env}-{layer}-{source} (e.g. dev-bronze-salesforce). Leave empty for one workspace covering the whole layer (e.g. dev-gold)."
  default     = ""
}

variable "capacity_id" {
  type        = string
  description = "Microsoft Fabric capacity ID (UUID) — must exist before workspaces are created"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to Entra ID groups"
  default     = {}
}
