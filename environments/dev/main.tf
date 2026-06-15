module "bronze" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "bronze"
  capacity_id = var.capacity_id
}

module "silver" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "silver"
  capacity_id = var.capacity_id
}

module "gold" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "dev"
  layer       = "gold"
  capacity_id = var.capacity_id
}
