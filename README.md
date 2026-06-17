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
│       ├── main.tf               ← per-source bronze + silver (for_each) and a single gold
│       ├── outputs.tf
│       └── terraform.tfvars      ← capacity_id and data_sources for this environment
└── .claude/agents/ms-fabric-iac.md   ← Claude Code agent for IaC assistance
```

## What gets created

**Bronze and silver get one workspace per data source; gold is a single curated
workspace per environment.** The data sources are listed in each environment's
`terraform.tfvars` (`data_sources`). With the default three sources
(`salesforce`, `sap`, `web`), each environment produces **7 workspaces**
(3 bronze + 3 silver + 1 gold):

| | Bronze (per source) | Silver (per source) | Gold |
|---|---|---|---|
| dev  | `dev-bronze-salesforce`, `dev-bronze-sap`, `dev-bronze-web`    | `dev-silver-salesforce`, `dev-silver-sap`, `dev-silver-web`    | `dev-gold`  |
| test | `test-bronze-salesforce`, …                                    | `test-silver-salesforce`, …                                    | `test-gold` |
| prod | `prod-bronze-salesforce`, …                                    | `prod-silver-salesforce`, …                                    | `prod-gold` |

General formula per environment: `2 × N_sources + 1` workspaces.

Per workspace, the module creates:
- 1 Fabric workspace
- 1 Fabric lakehouse
- 4 Entra ID security groups (`admin`, `member`, `contributor`, `viewer`)
- 4 Fabric workspace role assignments (one per group)

This is the per-source layout (a hybrid of Options B and C). For the resource counts
and trade-offs of other workspace layouts, see
[§3 MS Fabric workspace layout](#3-ms-fabric-workspace-layout).

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| Fabric workspace (bronze/silver) | `{env}-{layer}-{source}` | `prod-bronze-salesforce` |
| Fabric workspace (gold) | `{env}-{layer}` | `prod-gold` |
| Entra ID group | `fabric-{workspace-name}-{role}` | `fabric-prod-bronze-salesforce-viewer` |

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

**Per data source at bronze and silver; a single curated workspace at gold** — a
hybrid of Options B and C below. With `N` data sources this is `2N + 1` workspaces
per environment. Bronze and silver are source-aligned because ingestion and cleansing
logic differ per source; gold is conformed and aggregated across sources, so a single
workspace per environment is the natural permission and ownership boundary.

The earlier pure per-layer layout (Option B, one workspace per layer) is described
below as the simplest starting point; the options are kept for context and for
deciding when to move further (e.g. to full per-domain, Option D).

#### The design space

Workspace layout is the product of up to three independent dimensions:

| Dimension | Values | Fixed? |
|---|---|---|
| Environment | `dev` / `test` / `prod` | Yes — always a separate workspace |
| Layer | `bronze` / `silver` / `gold` | Yes — drives the permission boundary |
| Data source / domain | `salesforce`, `sap`, `web`, … | Optional — the variable you are weighing |

Environment is non-negotiable (it is the blast-radius and capacity boundary). The
real decision is how finely you slice the **layer** and **data-source** dimensions.
The four options below are ordered from coarsest to finest. Total workspace count is
shown for the three-environment case.

#### Option A — One workspace per environment (3 workspaces)

All three lakehouses live inside a single workspace per environment.

```
dev    ── bronze_lh, silver_lh, gold_lh
test   ── bronze_lh, silver_lh, gold_lh
prod   ── bronze_lh, silver_lh, gold_lh
```

Simplest to operate, but all three layers share one permission boundary. You cannot
grant a consumer Gold-only read access without also exposing Bronze and Silver. Fine
for a prototype or a single small team; outgrown quickly.

#### Option B — One workspace per layer per environment (9 workspaces)

```
dev-bronze    dev-silver    dev-gold
test-bronze   test-silver   test-gold
prod-bronze   prod-silver   prod-gold
```

Each layer has its own permission boundary. A Gold consumer group has `Viewer` on
`prod-gold` and zero access to `prod-bronze` or `prod-silver`. This was the original
layout and is the simplest starting point. Trade-off: all sources land together in
the single `{env}-bronze` workspace — fine until sources multiply or need separate
ownership/schedules, which is exactly why this repo now splits bronze/silver per
source (see "The choice" above).

#### Option C — Per data source at Bronze, per layer above (chosen if sources grow)

This is the "one workspace per data source" idea applied where it actually pays off:
the **Bronze** layer, where raw ingestion happens. Each source has its own ingestion
logic, schedule, and owning team, so each gets its own workspace. Silver and Gold
stay per-layer because by then data is conformed and modelled by domain, not by
source.

```
dev-bronze-salesforce    dev-bronze-sap    dev-bronze-web    dev-silver    dev-gold
test-bronze-salesforce   test-bronze-sap   test-bronze-web   test-silver   test-gold
prod-bronze-salesforce   prod-bronze-sap   prod-bronze-web   prod-silver   prod-gold
```

Count: `(N_sources + 2) × 3 environments`. With 3 sources → 15 workspaces.

Benefits: each source team owns and is billed for its own ingestion workspace;
a noisy or broken source is isolated; onboarding a new source is a single new module
call, no change to existing workspaces. Trade-off: more workspaces, and Silver now
reads from several Bronze workspaces via shortcuts instead of one.

#### Option D — Full data-source / domain across all layers (N × 9)

Every domain gets its own bronze/silver/gold stack per environment.

```
dev-finance-bronze    dev-finance-silver    dev-finance-gold
dev-logistics-bronze  dev-logistics-silver  dev-logistics-gold
prod-finance-bronze   prod-finance-silver   prod-finance-gold
...
```

Count: `N_domains × 3 layers × 3 environments`. With 2 domains → 18 workspaces.

Maximum isolation and clear domain ownership end-to-end (a data-mesh shape). Cost:
workspace count grows fast and cross-domain Gold reporting needs more shortcuts. Only
justified once domains have genuinely separate teams and governance.

#### Comparison

| Option | Workspaces (3 env) | Bronze split by | Silver/Gold split by | Use when |
|---|---|---|---|---|
| A | 3 | — | — | Prototype, one small team |
| B (chosen) | 9 | — | layer | Few sources, one data team |
| C | (N+2)×3 | data source | layer | Many sources / per-source ownership |
| D | N×9 | domain | domain | Multiple autonomous domain teams |

#### What gets created per option

Every workspace is built from the same block: **1 Fabric workspace · 1 lakehouse ·
4 Entra ID security groups (admin/member/contributor/viewer) · 4 role assignments**
= 10 resources. (Option A is the exception — it puts 3 lakehouses in one workspace
and scopes the 4 groups to that single workspace, so its permission boundary is the
whole environment.)

Totals are given for the three-environment case. `N` = number of data sources (C) or
domains (D).

**Chosen layout — per-source bronze + silver, single gold (`2N + 1` workspaces)**

Worked example with **N = 3** sources → `2×3 + 1 = 7` workspaces per env, 21 total:

| Resource | Per workspace | Total (21 ws) | Formula (3 env) |
|---|---|---|---|
| Fabric workspace | 1 | 21 | `(2N+1)×3` |
| Lakehouse | 1 | 21 | `(2N+1)×3` |
| Entra ID group | 4 | 84 | `(2N+1)×3×4` |
| Role assignment | 4 | 84 | `(2N+1)×3×4` |

**Option A — one workspace per environment (3 workspaces)**

| Resource | Per environment | Total (×3) |
|---|---|---|
| Fabric workspace | 1 | 3 |
| Lakehouse | 3 (bronze/silver/gold) | 9 |
| Entra ID group | 4 | 12 |
| Role assignment | 4 | 12 |

**Option B — one workspace per layer per environment (9 workspaces)**

| Resource | Per workspace | Total (9 ws) |
|---|---|---|
| Fabric workspace | 1 | 9 |
| Lakehouse | 1 | 9 |
| Entra ID group | 4 | 36 |
| Role assignment | 4 | 36 |

**Option C — per source at Bronze, per layer above ((N+2)×3 workspaces)**

Worked example with **N = 3** sources → `(3+2)×3 = 15` workspaces:

| Resource | Per workspace | Total (15 ws) | Formula |
|---|---|---|---|
| Fabric workspace | 1 | 15 | `(N+2)×3` |
| Lakehouse | 1 | 15 | `(N+2)×3` |
| Entra ID group | 4 | 60 | `(N+2)×3×4` |
| Role assignment | 4 | 60 | `(N+2)×3×4` |

**Option D — full data-source/domain across all layers (N×9 workspaces)**

Worked example with **N = 2** domains → `2×9 = 18` workspaces:

| Resource | Per workspace | Total (18 ws) | Formula |
|---|---|---|---|
| Fabric workspace | 1 | 18 | `N×3×3` |
| Lakehouse | 1 | 18 | `N×3×3` |
| Entra ID group | 4 | 72 | `N×3×3×4` |
| Role assignment | 4 | 72 | `N×3×3×4` |

#### How the module supports this

The `fabric_layer_workspace` module already takes the workspace name as input, so
moving from B to C or D is additive — you add `source` or `domain` to the naming
pattern and add module calls. No existing workspace is renamed or destroyed if you
keep B's names stable and only **add** new source/domain workspaces alongside them.

#### What each option means in Terraform code

The duplication *between* environment directories is the same for every option (it is
the deliberate blast-radius isolation from §1/§8). What changes is the shape of
`main.tf` *inside* each directory:

**Option A** — three lakehouses in one workspace, so the module is called once and
takes a list of lakehouses (or the module is reshaped to own all three):

```hcl
module "workspace" {
  source     = "../../modules/fabric_layer_workspace"
  name       = var.env
  lakehouses = ["bronze", "silver", "gold"]
}
```

**Option B (current)** — three explicit, hand-written module calls per directory.
Readable and greppable; duplication is low and constant (3 blocks):

```hcl
module "bronze" { source = "../../modules/fabric_layer_workspace"; name = "${var.env}-bronze" }
module "silver" { source = "../../modules/fabric_layer_workspace"; name = "${var.env}-silver" }
module "gold"   { source = "../../modules/fabric_layer_workspace"; name = "${var.env}-gold"   }
```

**Option C** — Bronze becomes a single `for_each` over a source list, so adding a
source is a one-line `tfvars` edit, not a new module block. Silver/Gold stay
explicit:

```hcl
module "bronze" {
  for_each = toset(var.bronze_sources)            # ["salesforce", "sap", "web"]
  source   = "../../modules/fabric_layer_workspace"
  name     = "${var.env}-bronze-${each.key}"
}
module "silver" { source = "../../modules/fabric_layer_workspace"; name = "${var.env}-silver" }
module "gold"   { source = "../../modules/fabric_layer_workspace"; name = "${var.env}-gold"   }
```

**Option D** — a nested `for_each` (domain × layer), typically driven by a map. Most
compact in code, but the indirection means you can no longer read off exactly what
exists without resolving the loop:

```hcl
locals {
  stacks = { for pair in setproduct(var.domains, ["bronze", "silver", "gold"]) :
             "${pair[0]}-${pair[1]}" => { domain = pair[0], layer = pair[1] } }
}
module "stack" {
  for_each = local.stacks
  source   = "../../modules/fabric_layer_workspace"
  name     = "${var.env}-${each.value.domain}-${each.value.layer}"
}
```

Degree of duplication / readability trade-off:

| Option | Module calls per directory | Add a workspace by | Readability |
|---|---|---|---|
| A | 1 | editing the lakehouse list | Highest |
| B | 3 explicit | adding a module block | High |
| C | 2 explicit + 1 `for_each` | one line in `tfvars` | Good |
| D | 1 `for_each` (map) | one line in `tfvars` | Lowest — needs loop resolution |

`for_each` (C/D) trades read-it-off-the-page clarity for less code and friction-free
growth. Stay explicit (B) while the list is short enough to read at a glance; reach
for `for_each` once you are adding sources or domains regularly.

#### Blast radius of the code shape

Per-environment isolation is unchanged across all options — separate state per
directory means a `dev` apply can never touch `prod` (§1). The options differ in
blast radius *within* a single environment directory:

- **Explicit blocks (A/B)** — each workspace is its own named resource address
  (`module.bronze`, `module.silver`, …). Removing one is a visible, reviewable code
  deletion. Hard to fat-finger; the diff shows exactly which workspace is going away.

- **`for_each` (C/D)** — every instance shares one resource address keyed by the
  source/domain name. Two specific hazards:
  - **Key removal = destroy.** Deleting `"sap"` from `var.bronze_sources` is a
    one-line `tfvars` edit, but `terraform plan` will show it as *destroy*
    `module.bronze["sap"]` — the workspace **and its lakehouse data** are removed.
    Low friction, high consequence. Always read the plan's destroy lines.
  - **Key rename = destroy + recreate.** Renaming a key (`"web"` → `"web_events"`)
    is not an in-place update; Terraform destroys the old instance and creates a new
    empty one. Use [`terraform state mv`](https://developer.hashicorp.com/terraform/cli/commands/state/mv)
    or a `moved` block to rename without data loss.
  - A broken change to the shared module block hits **all** instances in that
    `for_each` at once, rather than one explicit block you can plan in isolation.

- **Option A** has the largest per-unit blast radius: one workspace holds all three
  lakehouses, so destroying or misconfiguring it affects bronze, silver, and gold
  together — the opposite end from B's per-layer boundary.

Mitigations that apply regardless of option: review `terraform plan` for any
`destroy` line before applying, enable Fabric workspace soft-delete / OneLake
retention where available, and protect production lakehouses with
[`lifecycle { prevent_destroy = true }`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy)
in the module.

#### Recommendation

Start at **B**. Move Bronze to **C** the moment you have more than ~2–3 data sources
or a source needs its own owner, schedule, or capacity. Reserve **D** for when whole
domains have separate teams — adopting it earlier buys isolation you are not yet
paying the coordination cost to need.

#### When to revisit

Re-evaluate whenever you add a data source (does it deserve its own Bronze
workspace?) or a second business domain (is it time for D?). Both transitions are
additive module calls under the current design.

---

### 4. Module design and granularity

#### The choice

One module, `fabric_layer_workspace`, that creates everything for one layer in one
environment: the workspace, the lakehouse, the four Entra ID groups, and the four
role assignments.

#### Alternatives considered

**A — No module**: A hand-written copy of every resource definition for each
workspace. Not viable beyond a prototype.

**B — Two modules** (`fabric_workspace` + `entra_groups`): Useful if groups are
managed by a different team in a different state. In a single-team setup, adds
complexity without benefit.

**C — One module per resource type**: Maximum composability, but you manage all
dependency ordering (workspace before role assignment, group before role assignment)
in the calling code.

**D — One cohesive module (chosen)**: The workspace, lakehouse, groups, and role
assignments always have the same lifecycle — created and destroyed together. A single
`terraform destroy` cleanly removes all 10 artifacts for a workspace.

#### Extending the module

Add new Fabric items (notebooks, data pipelines, warehouses) to
`modules/fabric_layer_workspace/main.tf`. Every workspace instantiation (each
per-source bronze/silver and the single gold) picks up the change on the next apply.
Use a boolean variable (e.g. `enable_data_pipeline = false`) for optional items.

---

### 5. Entra ID group strategy

#### The choice

Four security groups per workspace, one per Fabric role:

```
fabric-{workspace-name}-admin
fabric-{workspace-name}-member
fabric-{workspace-name}-contributor
fabric-{workspace-name}-viewer
```

e.g. `fabric-prod-bronze-salesforce-viewer`, `fabric-prod-gold-admin`.

Total: 4 roles × (`2N + 1`) workspaces per environment. With 3 sources across three
environments that is 4 × 7 × 3 = **84 groups**.

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
| Fabric workspace (bronze/silver) | `{env}-{layer}-{source}` | Env-first groups all dev workspaces together; source suffix keeps each source's stack adjacent |
| Fabric workspace (gold) | `{env}-{layer}` | Gold is a single per-env workspace, so no source suffix |
| Entra ID group | `fabric-{workspace-name}-{role}` | Mirrors the workspace name so a group's scope is obvious; `fabric-` prefix namespaces it from the rest of the tenant |
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

Each silver workspace needs to read from its matching bronze lakehouse
(`{env}-silver-{source}` ← `{env}-bronze-{source}`). The single gold workspace needs
to read from *all* silver workspaces. They are in separate workspaces with no
automatic data sharing.

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

For shortcuts or pipeline reads to work, the service principal running the
`{env}-silver-{source}` job needs at least `Viewer` on `{env}-bronze-{source}` — add
it to the `fabric-{env}-bronze-{source}-viewer` group. The gold job needs `Viewer` on
every `{env}-silver-{source}` it consumes.

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
