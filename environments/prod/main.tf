module "bronze" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "prod"
  layer       = "bronze"
  capacity_id = var.capacity_id
}

module "silver" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "prod"
  layer       = "silver"
  capacity_id = var.capacity_id
}

module "gold" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "prod"
  layer       = "gold"
  capacity_id = var.capacity_id
}
