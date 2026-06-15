output "workspace_id" {
  value       = fabric_workspace.this.id
  description = "Fabric workspace ID"
}

output "workspace_name" {
  value       = fabric_workspace.this.display_name
  description = "Fabric workspace display name"
}

output "lakehouse_id" {
  value       = fabric_lakehouse.this.id
  description = "Fabric lakehouse ID"
}

output "group_object_ids" {
  value = {
    admin       = azuread_group.admin.object_id
    member      = azuread_group.member.object_id
    contributor = azuread_group.contributor.object_id
    viewer      = azuread_group.viewer.object_id
  }
  description = "Entra ID group object IDs keyed by Fabric role"
}
