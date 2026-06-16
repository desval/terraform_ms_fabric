# Bronze and silver: one workspace per data source.
module "bronze" {
  for_each    = toset(var.data_sources)
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "bronze"
  data_source = each.key
  capacity_id = var.capacity_id
}

module "silver" {
  for_each    = toset(var.data_sources)
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "silver"
  data_source = each.key
  capacity_id = var.capacity_id
}

# Gold: a single curated workspace aggregating across all sources.
module "gold" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "gold"
  capacity_id = var.capacity_id
}
