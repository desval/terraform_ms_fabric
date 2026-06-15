output "workspaces" {
  description = "Workspace and lakehouse IDs for all test medallion layers"
  value = {
    bronze = {
      workspace_id = module.bronze.workspace_id
      lakehouse_id = module.bronze.lakehouse_id
      groups       = module.bronze.group_object_ids
    }
    silver = {
      workspace_id = module.silver.workspace_id
      lakehouse_id = module.silver.lakehouse_id
      groups       = module.silver.group_object_ids
    }
    gold = {
      workspace_id = module.gold.workspace_id
      lakehouse_id = module.gold.lakehouse_id
      groups       = module.gold.group_object_ids
    }
  }
}
