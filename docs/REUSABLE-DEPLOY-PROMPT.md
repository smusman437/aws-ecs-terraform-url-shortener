# Copy-Paste Prompt: Docker → AWS ECS (Terraform) — Any Project

> **How to use:** Open any dockerized project in Cursor (or another AI IDE).  
> Copy everything inside the fenced block below and paste it as your message.  
> The agent should read **this repo first**, then generate all files and docs automatically.

---

## ⬇️ START COPY HERE ⬇️

You are deploying **this repository** to **AWS ECS Fargate** using **Terraform**. Do not ask me to manually run dozens of commands — generate a complete, working setup like a production-ready template.

### Your job

1. **Analyze this project first** (read before writing anything):
   - `Dockerfile` — base image, `EXPOSE` port, `CMD`, platform hints
   - `docker-compose.yml` / `compose.yaml` if present
   - Main app entrypoint (`app.py`, `main.go`, `server.js`, `index.ts`, etc.)
   - Health/readiness endpoints if any
   - `.env.example` / env vars the app needs
   - Existing `README` for project name and purpose
   - **Apple Silicon:** note if we need `linux/arm64` for ECS + Docker build

2. **Derive values from the project** (do not invent random names):

   | Value | How to detect |
   |--------|----------------|
   | `project_name` | Repo folder name or `README` title (kebab-case, e.g. `my-api`) |
   | `container_port` | `EXPOSE` in Dockerfile or app listen port (default 8080) |
   | `health_check_path` | `/health`, `/healthz`, `/api/health`, or add a minimal one if missing |
   | `aws_region` | `us-east-1` unless I specify another |
   | `ecr_repository_name` | same as `project_name` |
   | `ecs_cluster_name` | `{project_name}-cluster` |
   | `ecs_service_name` | `{project_name}-service` |
   | `BASE_URL` env | ALB URL in prod; `http://localhost:{port}` locally |

3. **Generate the full file structure:**

```text
{project-root}/
├── Dockerfile                    # keep or improve existing
├── .dockerignore
├── .env.example
├── .gitignore                    # tfstate, .env, .terraform/
├── README.md                     # update with scripts + URLs
├── GUIDE.md                      # step-by-step what/why
├── TERRAFORM.md                  # terraform workflow + which file does what
├── PROD.md                       # prod.tfvars testing checklist
├── ECS_TERRAFORM_DEPLOY_PROMPT.md  # this prompt (optional copy)
└── infra/
    ├── main.tf                   # provider, ECR (force_delete=true), modules
    ├── variables.tf
    ├── terraform.tfvars.example
    ├── terraform.tfvars          # dev: 1 task, no autoscaling
    ├── prod.tfvars               # prod: 2 tasks, autoscaling 2-10
    └── modules/
        ├── networking/           # VPC, 2 public subnets, IGW, routes
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── ecs/                  # cluster, task (ARM64 if Mac ARM), ALB, SGs
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
└── scripts/
    ├── lib/common.sh             # AWS_PROFILE, AWS_PAGER="", helpers
    ├── local.sh                  # docker build + run locally
    ├── plan.sh [dev|prod]        # terraform plan ONLY (review)
    ├── deploy.sh [dev|prod]      # plan → confirm yes → apply → push → ECS
    ├── redeploy-app.sh [dev|prod] # app code only, NO terraform
    ├── deploy-image.sh           # build arm64/amd64 + push ECR
    ├── status.sh                 # ECS + ALB health
    ├── test-api.sh [url]         # curl tests + optional /apidocs
    └── destroy.sh [dev|prod]     # ecr --force → state rm → terraform destroy
```

4. **Terraform requirements:**
   - AWS provider `~> 5.0`, region from variable
   - **ECR** with `force_delete = true`
   - **ECS Fargate** with `runtime_platform { cpu_architecture = "ARM64" }` when Dockerfile targets ARM / dev on Apple Silicon
   - **ALB** → target group → health check on `{health_check_path}`
   - Security groups: ALB `:80` from internet; ECS `{container_port}` from ALB only
   - CloudWatch log group `/ecs/{project_name}`, retention 7 days
   - Outputs: `ecr_uri`, `api_url`
   - Comment every important block (why it exists)

5. **Scripts requirements:**
   - Default `AWS_PROFILE=terraform-user` (document that I use separate profiles)
   - `export AWS_PAGER=""` so AWS CLI never hangs on `(END)`
   - `deploy.sh`: **terraform plan** → I type `yes` → apply → push image → `ecs update-service --force-new-deployment` → wait for healthy
   - `destroy.sh`: `aws ecr delete-repository --force` → `terraform state rm aws_ecr_repository.*` if needed → `terraform destroy`
   - `redeploy-app.sh`: only when app/Dockerfile changed, not `infra/*.tf`

6. **App requirements:**
   - App must listen on `0.0.0.0` and `{container_port}` (required for Docker/ECS)
   - Add **`GET {health_check_path}`** returning `{"status":"ok"}` if missing
   - Optional but preferred: **Swagger UI** at `/apidocs` (Flasgger for Python, or framework equivalent)

7. **Documentation requirements:**
   - `GUIDE.md`: phases (local → AWS CLI → terraform → ECR → ECS → destroy)
   - `TERRAFORM.md`: what is terraform, plan/apply/destroy, which file, what to run after code vs infra changes
   - `PROD.md`: `./scripts/plan.sh prod` then `./scripts/deploy.sh prod`
   - Table: **app-only change** → `redeploy-app.sh` | **infra change** → `plan.sh` + `deploy.sh`

8. **Do NOT:**
   - Commit secrets, `terraform.tfstate`, or real `.env`
   - Use plain `aws configure` without `--profile` in docs
   - Skip `terraform plan` before apply
   - Hardcode my AWS account ID

9. **After generating, give me a short summary:**
   - Detected: project name, port, health path, language
   - Commands: local run, first deploy, app redeploy, destroy
   - Swagger URL if added
   - Note: install Terraform **darwin_arm64** on Apple Silicon

### Assumptions (override only if this repo clearly differs)

- IAM user `terraform-user` with `AdministratorAccess` already exists
- I run: `export AWS_PROFILE=terraform-user`
- First-time: `aws configure --profile terraform-user`
- Dev: 1 ECS task; Prod: 2 tasks + CPU autoscaling 2–10

### Reference implementation

If helpful, mirror patterns from a working URL-shortener ECS+Terraform repo (Flask + Fargate + ALB + scripts). Adapt all names and ports to **this** project.

**Start by listing what you detected from this repo, then generate all files.**

## ⬆️ END COPY ⬆️

---

## Optional: add your project-specific overrides

Paste these lines **below** the main prompt if needed:

```text
OVERRIDES:
- project_name: my-custom-name
- container_port: 3000
- health_check_path: /api/health
- aws_region: eu-west-1
- AWS_PROFILE: my-terraform-profile
- Skip Swagger: no
- Use linux/amd64 instead of arm64: yes
```

---

## Quick reference (for you, not the AI)

| Goal | Command (after AI generates files) |
|------|-------------------------------------|
| Local | `./scripts/local.sh` |
| Preview infra | `./scripts/plan.sh dev` |
| First deploy | `./scripts/deploy.sh dev` |
| App code only | `./scripts/redeploy-app.sh dev` |
| Swagger | `http://localhost:{port}/apidocs` |
| Destroy | `./scripts/destroy.sh dev` |
| Prod later | `./scripts/deploy.sh prod` |

---

## One-line version (minimal paste)

```text
Analyze this dockerized repo (Dockerfile port, app entrypoint, health route). Generate full AWS ECS Fargate + Terraform infra (VPC, ALB, ECR, ECS ARM64), scripts (plan.sh, deploy.sh, redeploy-app.sh, destroy.sh with ECR force-delete), GUIDE.md + TERRAFORM.md. Derive project_name from repo. Add /health if missing. Swagger at /apidocs if Python. terraform plan before apply. Do not hardcode account ID.
```
