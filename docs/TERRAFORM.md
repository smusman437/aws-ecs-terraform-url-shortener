# Terraform — What It Is, How It Works, and Your Project Files

## What is Terraform?

**Terraform** is a tool that reads **configuration files** (`.tf`) and **creates or updates real cloud resources** on AWS for you.

| Without Terraform | With Terraform |
|-------------------|----------------|
| Click in AWS Console to create VPC, ECS, ALB… | Write code once in `infra/` |
| Hard to repeat or share | Same code deploys again for a teammate |
| No history of what exists | `terraform.tfstate` tracks what Terraform manages |

Think of it as: **infrastructure as code** — your AWS setup is versioned in Git like your app.

---

## How Terraform works (4 commands)

```mermaid
flowchart LR
  A[You write .tf files] --> B[terraform init]
  B --> C[terraform plan]
  C --> D[terraform apply]
  D --> E[AWS resources exist]
  E --> F[terraform.tfstate records them]
```

| Command | What it does | When to run |
|---------|----------------|-------------|
| **`terraform init`** | Downloads AWS plugin, prepares folder | First time, or after adding modules/providers |
| **`terraform plan`** | Dry run — shows what **would** change (no changes yet) | Before apply, to review |
| **`terraform apply`** | **Creates or updates** resources on AWS | Deploy infrastructure |
| **`terraform destroy`** | **Deletes** everything Terraform created | Teardown (`./scripts/destroy.sh`) |

Terraform compares:

1. **Your `.tf` files** (what you *want*)
2. **`terraform.tfstate`** (what Terraform *last created*)
3. **Real AWS** (what *actually* exists)

Then it figures out: add, change, or delete.

---

## What is `terraform.tfstate`?

A JSON file Terraform writes after `apply`. It stores:

- Resource IDs (e.g. VPC id `vpc-08560dac...`)
- Links between resources

**Why it matters:** Without state, Terraform would not know what to destroy or update.

| File | In Git? | Why |
|------|---------|-----|
| `terraform.tfstate` | **No** (gitignored) | Can contain secrets; personal to your machine |
| `terraform.tfstate.backup` | **No** | Auto backup before each apply |

---

## Your `infra/` folder — every file explained

```
infra/
├── main.tf                 # Entry point: provider, ECR, module calls, outputs
├── variables.tf            # Declares inputs (region, desired_count, etc.)
├── terraform.tfvars        # Dev values for those inputs (gitignored)
├── terraform.tfvars.example # Template to copy
├── prod.tfvars             # Prod values (2 tasks, autoscaling)
├── .terraform.lock.hcl     # Locks provider version (commit this)
├── terraform.tfstate       # What exists in AWS (do NOT commit)
└── modules/
    ├── networking/         # VPC, subnets, internet gateway
    └── ecs/                # ECS, ALB, security groups, logs
```

### `main.tf` — the root

| Block | Why it exists |
|-------|----------------|
| `terraform { required_providers }` | Tells Terraform to use AWS provider v5.x |
| `provider "aws"` | Region and credentials (from `AWS_PROFILE`) |
| `resource "aws_ecr_repository"` | Docker image storage in AWS |
| `module "networking"` | Reusable network stack |
| `module "ecs"` | Reusable compute + load balancer stack |
| `output "api_url"` | Prints public URL after apply |

### `variables.tf` — inputs (declarations only)

Defines **names and types**, not values:

```hcl
variable "desired_count" {
  description = "Number of ECS tasks"
  type        = number
  default     = 1
}
```

### `terraform.tfvars` / `prod.tfvars` — actual values

```hcl
desired_count = 1        # dev
enable_autoscaling = false
```

`deploy.sh dev` uses `terraform.tfvars`.  
`deploy.sh prod` uses `prod.tfvars`.

### `modules/networking/` — network layer

| File | Purpose |
|------|---------|
| `main.tf` | VPC, 2 public subnets, internet gateway, route tables |
| `variables.tf` | Inputs from root (`project_name`, `aws_region`) |
| `outputs.tf` | Exports `vpc_id`, `public_subnet_ids` to ECS module |

**Why a module?** Keeps networking separate from ECS — easier to read and reuse.

### `modules/ecs/` — app runtime layer

| File | Purpose |
|------|---------|
| `main.tf` | ECS cluster, task definition, service, ALB, security groups, autoscaling, alarms |
| `variables.tf` | Inputs: `vpc_id`, `ecr_repository_url`, `desired_count`, etc. |
| `outputs.tf` | Exports `api_url` (ALB DNS name) |

**Important line in ECS task definition:**

```hcl
runtime_platform {
  cpu_architecture = "ARM64"   # matches Docker built on Apple Silicon
}
```

### `.terraform/` folder (auto-generated)

Created by `terraform init`. Contains downloaded AWS provider binary. **Do not edit.** Can be deleted and recreated with `terraform init`.

### `.terraform.lock.hcl`

Locks exact provider version so everyone gets the same behavior. **Safe to commit.**

---

## Terraform vs Docker vs ECS — who does what?

| Layer | Tool | What it manages |
|-------|------|-----------------|
| **App code** | `app.py` | Business logic |
| **Container** | `Dockerfile` | How app runs inside a box |
| **Image in AWS** | `deploy-image.sh` | Push image to ECR |
| **Infrastructure** | **Terraform** | VPC, ECS, ALB, IAM, ECR repo |
| **Running containers** | **ECS** | Keeps N copies of your image running |

Terraform does **not** run your Python code. It creates the **places** where ECS runs your Docker image.

---

## After first deploy — what to run when you change something?

### Decision table

| You changed… | What to run | Why |
|--------------|-------------|-----|
| **`app.py` only** | `./scripts/redeploy-app.sh dev` | Infra unchanged; only new Docker image |
| **`Dockerfile` / `requirements.txt`** | `./scripts/redeploy-app.sh dev` | New image layers |
| **`infra/*.tf`** | `./scripts/plan.sh dev` then `./scripts/deploy.sh dev` | Review plan, then apply |
| **Preview infra only** | `./scripts/plan.sh dev` or `prod` | No AWS changes |
| **App + Terraform** | `./scripts/deploy.sh dev` | Plan → apply → image → ECS |
| **Not sure** | `./scripts/deploy.sh dev` | Safest |

### Fast path — app code only

```bash
export AWS_PROFILE=terraform-user
./scripts/redeploy-app.sh dev
```

### Full path — infra + app (includes terraform plan for review)

```bash
export AWS_PROFILE=terraform-user
./scripts/deploy.sh dev
```

Shows **terraform plan** first, then asks you to type `yes` before apply.

### Prod (when ready to test)

See **[PROD.md](./PROD.md)** — `./scripts/plan.sh prod` then `./scripts/deploy.sh prod`

### Examples

| Change | Command |
|--------|---------|
| Fixed bug in `shorten()` | `deploy-image.sh` + `ecs update-service` |
| Bumped `desired_count` in `terraform.tfvars` | `./scripts/deploy.sh dev` |
| Added environment variable in `modules/ecs/main.tf` | `./scripts/deploy.sh dev` |
| Changed Flask port (unusual) | Terraform + image + redeploy → `deploy.sh dev` |

---

## Typical Terraform workflow (manual, if not using scripts)

```bash
export AWS_PROFILE=terraform-user
cd infra

terraform init                    # once per machine
terraform plan -var-file=terraform.tfvars   # review changes
terraform apply -var-file=terraform.tfvars  # type yes

# After changing .tf files:
terraform plan -var-file=terraform.tfvars   # see diff
terraform apply -var-file=terraform.tfvars
```

---

## Common questions

### Do I run `deploy.sh` every time I edit code?

**No.** Only when infrastructure changes or you want the all-in-one flow.  
For small app fixes: **push new image + force ECS deployment** (faster).

### Does Terraform deploy my Docker image?

**Partially.** Terraform creates the **ECR repository** and tells ECS **which image URL** to use (`:latest`).  
You still **build and push** the image with `deploy-image.sh` (or `deploy.sh` does it for you).

### What if I delete resources in the AWS Console?

Terraform state will be **out of sync**. Next `apply` may recreate them or error.  
Prefer: change `.tf` files and run `apply`, or `./scripts/destroy.sh` for full cleanup.

### `plan` vs `apply`?

- **plan** = preview (safe, read-only)
- **apply** = actually change AWS

---

## Quick reference

```bash
# First time / full deploy
./scripts/deploy.sh dev

# App code only (faster)
./scripts/deploy-image.sh && aws ecs update-service ... --force-new-deployment

# Check live system
./scripts/status.sh
./scripts/test-api.sh

# Remove everything
./scripts/destroy.sh dev
```

See also: [GUIDE.md](./GUIDE.md) (scripts + phases), [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) (AWS architecture deep dive).
