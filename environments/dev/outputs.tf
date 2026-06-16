output "workspaces" {
  description = "Workspace and lakehouse IDs for all dev medallion layers. Bronze and silver are keyed by data source; gold is a single workspace."
  value = {
    bronze = {
      for src, mod in module.bronze : src => {
        workspace_id = mod.workspace_id
        lakehouse_id = mod.lakehouse_id
        groups       = mod.group_object_ids
      }
    }
    silver = {
      for src, mod in module.silver : src => {
        workspace_id = mod.workspace_id
        lakehouse_id = mod.lakehouse_id
        groups       = mod.group_object_ids
      }
    }
    gold = {
      workspace_id = module.gold.workspace_id
      lakehouse_id = module.gold.lakehouse_id
      groups       = module.gold.group_object_ids
    }
  }
}
