capacity_id = "00000000-0000-0000-0000-000000000000"

# Each source gets its own bronze and silver workspace, e.g. test-bronze-salesforce.
# Add or remove sources here. NOTE: removing a source destroys its bronze and
# silver workspaces (and their lakehouse data) on the next apply.
data_sources = ["salesforce", "sap", "web"]
