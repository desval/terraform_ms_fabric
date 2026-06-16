# Get the capacity ID from:
#   Azure portal → Fabric capacity resource → Properties → Capacity ID
# or:
#   az fabric capacity show --name <name> --resource-group <rg> --query id -o tsv
capacity_id = "00000000-0000-0000-0000-000000000000"

# Each source gets its own bronze and silver workspace, e.g. dev-bronze-salesforce.
# Add or remove sources here. NOTE: removing a source destroys its bronze and
# silver workspaces (and their lakehouse data) on the next apply.
data_sources = ["salesforce", "sap", "web"]
