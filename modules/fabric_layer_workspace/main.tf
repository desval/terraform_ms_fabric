locals {
  name_prefix = "${var.environment}-${var.layer}"

  layer_descriptions = {
    bronze = "Raw data ingestion — unmodified source data"
    silver = "Cleansed and validated data — business rules applied"
    gold   = "Business-ready curated data — aggregates and KPIs"
  }
}

# ── Entra ID security groups ─────────────────────────────────────────────────

resource "azuread_group" "admin" {
  display_name     = "fabric-${local.name_prefix}-admin"
  security_enabled = true
  description      = "Fabric workspace admins for ${local.name_prefix}"
}

resource "azuread_group" "member" {
  display_name     = "fabric-${local.name_prefix}-member"
  security_enabled = true
  description      = "Fabric workspace members for ${local.name_prefix}"
}

resource "azuread_group" "contributor" {
  display_name     = "fabric-${local.name_prefix}-contributor"
  security_enabled = true
  description      = "Fabric workspace contributors for ${local.name_prefix}"
}

resource "azuread_group" "viewer" {
  display_name     = "fabric-${local.name_prefix}-viewer"
  security_enabled = true
  description      = "Fabric workspace viewers for ${local.name_prefix}"
}

# ── MS Fabric workspace ───────────────────────────────────────────────────────

resource "fabric_workspace" "this" {
  display_name = local.name_prefix
  description  = "${title(var.environment)} — ${title(var.layer)}: ${local.layer_descriptions[var.layer]}"
  capacity_id  = var.capacity_id
}

# ── Lakehouse ─────────────────────────────────────────────────────────────────

resource "fabric_lakehouse" "this" {
  workspace_id = fabric_workspace.this.id
  display_name = var.layer
  description  = local.layer_descriptions[var.layer]
}

# ── Workspace role assignments ────────────────────────────────────────────────

resource "fabric_workspace_role_assignment" "admin" {
  workspace_id   = fabric_workspace.this.id
  principal_id   = azuread_group.admin.object_id
  principal_type = "Group"
  role           = "Admin"
}

resource "fabric_workspace_role_assignment" "member" {
  workspace_id   = fabric_workspace.this.id
  principal_id   = azuread_group.member.object_id
  principal_type = "Group"
  role           = "Member"
}

resource "fabric_workspace_role_assignment" "contributor" {
  workspace_id   = fabric_workspace.this.id
  principal_id   = azuread_group.contributor.object_id
  principal_type = "Group"
  role           = "Contributor"
}

resource "fabric_workspace_role_assignment" "viewer" {
  workspace_id   = fabric_workspace.this.id
  principal_id   = azuread_group.viewer.object_id
  principal_type = "Group"
  role           = "Viewer"
}
