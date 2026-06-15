# MS Fabric IaC

Terraform project for provisioning Microsoft Fabric workspaces, lakehouses, and
Entra ID access groups across dev, test, and prod environments, following the
medallion architecture (Bronze → Silver → Gold).

## Quick start

**Prerequisites**: Terraform ≥ 1.9, Azure CLI, a Fabric capacity that already exists.

```bash
# 1. Create the Terraform state backend (once, before anything else)
az group create -n rg-terraform-state -l westeurope
az storage account create -n stfabrictfstate -g rg-terraform-state --sku Standard_LRS
az storage container create -n tfstate --account-name stfabrictfstate

# 2. Fill in your capacity ID
#    az fabric capacity show --name <name> -g <rg> --query id -o tsv
#    Paste the UUID into environments/<env>/terraform.tfvars

# 3. Authenticate
az login
az account set --subscription "<subscription-id>"

# 4. Deploy an environment
cd environments/dev
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Repository layout

```
terraform_ms_fabric/
├── modules/
│   └── fabric_layer_workspace/   ← reusable module: workspace + lakehouse + Entra groups + role assignments
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/                      ← one Terraform root per environment
│   ├── test/
│   └── prod/
│       ├── providers.tf          ← provider versions + Azure Blob state backend
│       ├── variables.tf
│       ├── main.tf               ← calls the module for bronze, silver, gold
│       ├── outputs.tf
│       └── terraform.tfvars      ← capacity_id for this environment
└── .claude/agents/ms-fabric-iac.md   ← Claude Code agent for IaC assistance
```

## What gets created

Each environment call creates **9 workspaces** via the `fabric_layer_workspace` module:

| | Bronze | Silver | Gold |
|---|---|---|---|
| dev  | `dev-bronze`  | `dev-silver`  | `dev-gold`  |
| test | `test-bronze` | `test-silver` | `test-gold` |
| prod | `prod-bronze` | `prod-silver` | `prod-gold` |

Per workspace, the module creates:
- 1 Fabric workspace
- 1 Fabric lakehouse
- 4 Entra ID security groups (`admin`, `member`, `contributor`, `viewer`)
- 4 Fabric workspace role assignments (one per group)

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| Fabric workspace | `{env}-{layer}` | `prod-gold` |
| Entra ID group | `fabric-{env}-{layer}-{role}` | `fabric-prod-gold-viewer` |

## Providers

| Provider | Purpose |
|---|---|
| `microsoft/fabric ~> 1.0` | Fabric workspaces, lakehouses, role assignments |
| `hashicorp/azuread ~> 3.0` | Entra ID security groups |

Terraform state is stored in Azure Blob Storage (one state file per environment).
This is a Terraform bookkeeping mechanism — it has no relationship to Fabric itself.

---

## Design decisions

This section explains every significant design choice, why it was made, what the
alternatives were, and when you might want to revisit it.

### Table of contents

1. [Terraform project structure](#1-terraform-project-structure)
2. [State isolation strategy](#2-state-isolation-strategy)
3. [MS Fabric workspace layout](#3-ms-fabric-workspace-layout)
4. [Module design and granularity](#4-module-design-and-granularity)
5. [Entra ID group strategy](#5-entra-id-group-strategy)
6. [Naming conventions](#6-naming-conventions)
7. [Capacity management](#7-capacity-management)
8. [DRY level: native Terraform vs Terragrunt](#8-dry-level-native-terraform-vs-terragrunt)
9. [Cross-workspace data access](#9-cross-workspace-data-access)
10. [What is deliberately out of scope](#10-what-is-deliberately-out-of-scope)

---

### 1. Terraform project structure

#### The choice

One directory per environment, each being a standalone Terraform root module:

```
environments/
├── dev/
├── test/
└── prod/
```

#### Alternatives considered

**A — Single root module, `terraform.workspace` for environments**

```bash
terraform workspace select prod
terraform apply
```

Terraform workspaces are widely recommended *against* for environment separation.
The state files live in the same backend container, the code is identical for all
environments (so you cannot express env-specific differences cleanly), and there is
no physical barrier between a `dev` apply and a `prod` apply — a typo in the
workspace name is enough to destroy the wrong environment.

**B — Single root module, `for_each` over environments**

```hcl
module "fabric" {
  for_each    = toset(["dev", "test", "prod"])
  source      = "./modules/fabric_layer_workspace"
  environment = each.key
}
```

This puts all three environments in a single state file. The blast radius of a broken
plan is all three environments simultaneously. You also cannot independently approve
a `test` change without also planning `dev` and `prod`.

**C — Separate directories (chosen)**

Each environment is a fully independent root module. A `terraform apply` in `dev/`
is physically incapable of touching `prod/` because they have separate state files,
separate provider authentication contexts, and no Terraform knowledge of each other.

Trade-off accepted: the three `providers.tf` files are near-identical. This
repetition is intentional — it is the price of blast-radius isolation.

#### When to revisit

If you add a fourth environment (e.g. `staging`), copying the directory is the right
move. If you find yourself managing ten or more environments, look at Terragrunt
(see §8).

---

### 2. State isolation strategy

#### The choice

Azure Blob Storage backend, one state file per environment:

```
tfstate/
├── fabric/dev/terraform.tfstate
├── fabric/test/terraform.tfstate
└── fabric/prod/terraform.tfstate
```

Note: this is Terraform's own bookkeeping — it tracks which resources have been
created so it can compute diffs. It has no relationship to Fabric itself.

#### Alternatives considered

**A — Local state**: Zero setup, works immediately. Unsuitable for team use: state
is on one person's machine, no locking, no history.

**B — Terraform Cloud / HCP Terraform**: Managed backend with a UI, run history, and
policy enforcement (Sentinel). Add this if you want a full GitOps approval workflow.

**C — Azure Blob Storage (chosen)**: Native to the Azure ecosystem, free at this
scale, supports state locking via blob leases, and keeps everything within your
tenant.

#### When to revisit

Move to Terraform Cloud if you want policy-as-code (Sentinel) or a team approval
workflow baked into the platform.

---

### 3. MS Fabric workspace layout

#### The choice

**One workspace per medallion layer per environment** — nine workspaces total.

#### Alternatives considered

**A — One workspace per environment**

All three lakehouses (bronze, silver, gold) inside a single workspace per env.
Simpler in the UI, but all three layers share the same permission boundary. You
cannot grant a data consumer Gold-only read access without also exposing Bronze and
Silver.

**B — One workspace per layer per environment (chosen)**

Each layer has its own permission boundary. A Gold consumer group has `Viewer` on
`prod-gold` and zero access to `prod-bronze` or `prod-silver`.

Trade-off accepted: nine workspaces instead of three. Cross-workspace data flow
requires OneLake shortcuts (see §9).

**C — Domain-driven layout**

```
dev-finance-bronze / dev-finance-silver / dev-finance-gold
dev-logistics-bronze / ...
```

Start with option B and move here when a second data domain is introduced — adding
a `domain` variable to the module is straightforward.

---

### 4. Module design and granularity

#### The choice

One module, `fabric_layer_workspace`, that creates everything for one layer in one
environment: the workspace, the lakehouse, the four Entra ID groups, and the four
role assignments.

#### Alternatives considered

**A — No module**: Nine copies of every resource definition. Not viable beyond a
prototype.

**B — Two modules** (`fabric_workspace` + `entra_groups`): Useful if groups are
managed by a different team in a different state. In a single-team setup, adds
complexity without benefit.

**C — One module per resource type**: Maximum composability, but you manage all
dependency ordering (workspace before role assignment, group before role assignment)
in the calling code.

**D — One cohesive module (chosen)**: The workspace, lakehouse, groups, and role
assignments always have the same lifecycle — created and destroyed together. A single
`terraform destroy` cleanly removes all nine artifacts for a layer.

#### Extending the module

Add new Fabric items (notebooks, data pipelines, warehouses) to
`modules/fabric_layer_workspace/main.tf`. All nine instantiations pick up the
change on the next apply. Use a boolean variable (e.g. `enable_data_pipeline =
false`) for optional items.

---

### 5. Entra ID group strategy

#### The choice

Four security groups per workspace, one per Fabric role:

```
fabric-{env}-{layer}-admin
fabric-{env}-{layer}-member
fabric-{env}-{layer}-contributor
fabric-{env}-{layer}-viewer
```

Total: 4 roles × 9 workspaces = **36 groups**.

#### Fabric roles

| Role | Can do |
|---|---|
| Admin | Full control, including deleting the workspace and changing settings |
| Member | Create/edit/delete Fabric items; manage permissions below Member |
| Contributor | Create and edit Fabric items; cannot manage permissions |
| Viewer | Read-only access to Fabric items and their data |

#### Service principals

Automated processes (pipelines, ingestion jobs) should be added to a group rather
than given direct workspace access. Create an `azuread_service_principal` and add it
to the appropriate group via `azuread_group_member` in a separate `resources/`
directory.

---

### 6. Naming conventions

| Resource | Pattern | Rationale |
|---|---|---|
| Fabric workspace | `{env}-{layer}` | Env-first groups all dev workspaces together in the UI |
| Entra ID group | `fabric-{env}-{layer}-{role}` | `fabric-` prefix namespaces groups from the rest of the tenant |
| Terraform resource | Named by role, not display name | Avoids a destroy/recreate if the display name changes |

Avoid `bronze-dev` (layer-first) — workspaces sort by name in the Fabric UI and
you want all `dev-*` together, not all `bronze-*`.

Avoid human-readable group names like `Gold Production Viewers` — these break
automation and are hard to filter programmatically.

---

### 7. Capacity management

#### The choice

Fabric capacity is **not managed in this repository**. The `capacity_id` is an
input variable pointing to a capacity that must already exist.

#### Why

Fabric capacity is a billing resource. Creating or destroying it requires
subscription-level permissions that the workspace provisioning service principal
should not have, and its lifecycle (purchasing, scaling, pausing) is a separate
concern owned by a platform or FinOps team.

#### Shared vs separate capacity

| | Shared capacity | Separate capacity per env |
|---|---|---|
| Cost | Lower | Higher |
| Isolation | CU contention possible | Full isolation |
| Typical use | Dev + Test share one SKU | Prod on its own SKU |

Use different `capacity_id` values in `dev/terraform.tfvars` vs
`prod/terraform.tfvars` to implement this split.

---

### 8. DRY level: native Terraform vs Terragrunt

#### Current state

The module eliminates the 9-resource repetition. What remains repeated across the
three environment directories is intentional: `providers.tf` (differs only in the
backend key) and `main.tf` (differs only in the environment name). A reader can
understand what is deployed to production without following any abstraction.

#### When the repetition becomes a problem

- More than ~5 environments
- `providers.tf` has drifted between environments and is causing bugs
- Adding a global variable requires editing every environment file

#### Terragrunt

[Terragrunt](https://terragrunt.gruntwork.io/) generates provider and backend
configuration from a shared root. Adding a fourth environment becomes a three-line
file. Trade-off: additional tool dependency, not from HashiCorp.

**Recommendation**: stay on native Terraform for now; migrate when environments
exceed five or provider-config drift becomes a maintenance burden.

---

### 9. Cross-workspace data access

This is the most important open question — a data-layer concern, not a permissions
concern.

#### The problem

The silver workspace needs to read from the bronze lakehouse. The gold workspace
needs to read from silver. They are in separate workspaces with no automatic data
sharing.

#### Options

**A — OneLake shortcuts (recommended)**

A shortcut is a pointer from one lakehouse to another. Bronze data appears as a
local folder inside the silver lakehouse. No data is copied. Shortcuts can be
created via the Fabric REST API today; add a `fabric_lakehouse_shortcut` resource
to the module when the Terraform provider supports it.

**B — Data pipelines with explicit copy steps**

The pipeline handles the cross-workspace read explicitly. More control, but copies
data rather than referencing it.

**C — Shared lakehouse in a common workspace**

A fourth `{env}-shared` workspace. Increases complexity and adds a cross-cutting
permission concern.

#### Access required

For shortcuts or pipeline reads to work, the service principal running the silver
job needs at least `Viewer` on `{env}-bronze`. Add it to the
`fabric-{env}-bronze-viewer` Entra group.

---

### 10. What is deliberately out of scope

**Fabric capacity provisioning** — managed separately; see §7.

**User onboarding** — adding people to groups is an HR/IT ops concern. The groups
are created by Terraform; membership is managed by the identity team. Coupling
personnel changes to infrastructure PRs slows both.

**Fabric item definitions** — notebooks, data pipelines, and semantic models are
owned by the data engineering team and deployed via Azure DevOps or Fabric
Deployment Pipelines. IaC provisions the container (workspace + lakehouse); content
is a separate lifecycle.

**Networking and private endpoints** — if using Fabric Private Link, private DNS and
endpoint resources belong in a separate `networking/` root module. Workspace
provisioning should not depend on network topology.

**Monitoring and alerting** — capacity utilisation and job failure alerts belong in
a separate `monitoring/` root module or are managed by the platform team via Azure
Monitor.
