# Bronze and silver: one workspace per data source.
module "bronze" {
  for_each    = toset(var.data_sources)
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "bronze"
  data_source = each.key
  capacity_id = var.capacity_id
}

module "silver" {
  for_each    = toset(var.data_sources)
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "silver"
  data_source = each.key
  capacity_id = var.capacity_id
}

# Gold: a single curated workspace aggregating across all sources.
module "gold" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "gold"
  capacity_id = var.capacity_id
}
