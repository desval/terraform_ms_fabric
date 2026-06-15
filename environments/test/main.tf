module "bronze" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "bronze"
  capacity_id = var.capacity_id
}

module "silver" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "silver"
  capacity_id = var.capacity_id
}

module "gold" {
  source      = "../../modules/fabric_layer_workspace"
  environment = "test"
  layer       = "gold"
  capacity_id = var.capacity_id
}
