variable "capacity_id" {
  type        = string
  description = "Microsoft Fabric capacity ID — find it in the Azure portal under the Fabric capacity resource"
}

variable "data_sources" {
  type        = list(string)
  description = "Data sources that each get their own bronze and silver workspace (e.g. [\"salesforce\", \"sap\", \"web\"]). Gold is a single workspace and does not use this list."

  validation {
    condition     = length(var.data_sources) == length(toset(var.data_sources))
    error_message = "data_sources must not contain duplicates."
  }
}
