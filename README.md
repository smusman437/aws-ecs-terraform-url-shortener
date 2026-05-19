# URL Shortener — AWS ECS + Terraform

A production-style URL shortener API built with Flask, Docker, and AWS (ECR, ECS Fargate, ALB). Infrastructure is defined with Terraform.

## Features

- `POST /shorten` — create a short code for a long URL
- `GET /{code}` — redirect to the original URL
- `GET /health` — health check for load balancers
- `GET /all` — list all mappings (debug only; remove in real production)

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop) | Build and run containers |
| [Python 3.12+](https://www.python.org/downloads) | Optional: run Flask without Docker |
| [AWS account](https://aws.amazon.com/free) | Cloud deployment |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access |
| [Terraform 1.7+](https://developer.hashicorp.com/terraform/install) | Infrastructure as code |

## Easy commands (recommended)

```bash
export AWS_PROFILE=terraform-user

./scripts/local.sh              # Run on localhost:8080
./scripts/plan.sh dev           # Preview Terraform changes (no apply)
./scripts/deploy.sh dev         # Plan → apply → ECR → ECS (full deploy)
./scripts/redeploy-app.sh dev   # App code only (no Terraform)
./scripts/status.sh             # Check ECS + ALB health
./scripts/test-api.sh           # Test live or local API
./scripts/destroy.sh dev        # Tear down all AWS resources
```

See **[GUIDE.md](./GUIDE.md)** for step-by-step explanations (what, why, in order) and destroy instructions.  
See **[TERRAFORM.md](./TERRAFORM.md)** for what Terraform is, how it works, which files matter, and what to run after code changes.  
Each script in `scripts/` includes inline comments on every important line.

## Project structure

```
├── app.py                 # Flask API
├── requirements.txt       # Python dependencies
├── Dockerfile             # Container image recipe
├── .env.example           # Environment variable template
├── GUIDE.md               # Step-by-step guide + script usage
├── ROADMAP.md             # Architecture, env vars, deep reference
├── scripts/
│   ├── plan.sh            # Terraform plan only (review)
│   ├── deploy.sh          # Plan + apply + ECR + ECS
│   ├── redeploy-app.sh    # App code only (fast)
│   ├── destroy.sh         # One-command teardown
│   ├── test-api.sh        # Health + shorten + redirect tests
│   ├── status.sh          # ECS / ALB status
│   ├── local.sh           # Run locally with Docker
│   └── deploy-image.sh    # Build + push to ECR only
└── infra/
    ├── main.tf            # Root Terraform (ECR + modules)
    ├── variables.tf
    ├── terraform.tfvars   # Dev defaults (gitignored — copy from example)
    ├── prod.tfvars        # Production values
    └── modules/
        ├── networking/    # VPC, subnets, IGW
        └── ecs/           # ECS, ALB, auto-scaling, alarms
```

## Quick start — local (Docker)

```bash
# From project root
docker build -t url-shortener .
docker run -p 8080:8080 url-shortener
```

Test:

```bash
curl http://localhost:8080/health

curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.google.com"}'

# Replace SHORT_CODE with the code from the response
curl -L http://localhost:8080/SHORT_CODE
```

Optional: copy `.env.example` to `.env` and set `BASE_URL` if you use a different host/port.

## Quick start — AWS production

1. **Configure AWS CLI** (one time):

   ```bash
   aws configure
   aws sts get-caller-identity
   ```

2. **Export deployment variables**:

   ```bash
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export AWS_REGION=us-east-1
   ```

3. **Provision infrastructure**:

   ```bash
   cd infra
   terraform init
   terraform apply -var-file=terraform.tfvars   # dev
   # or
   terraform apply -var-file=prod.tfvars        # production
   ```

   Save outputs: `ecr_uri` and `api_url`.

4. **Push Docker image to ECR**:

   ```bash
   cd ..
   chmod +x scripts/deploy-image.sh
   ./scripts/deploy-image.sh
   ```

5. **Force ECS to pull the new image** (after first push or code changes):

   ```bash
   aws ecs update-service \
     --cluster url-shortener-cluster \
     --service url-shortener-service \
     --force-new-deployment \
     --region us-east-1
   ```

6. **Test live API** (use `api_url` from Terraform output):

   ```bash
   curl http://YOUR-ALB-DNS/health
   ```

## Environment variables

| Variable | Used by | Where to get it |
|----------|---------|-----------------|
| `BASE_URL` | Flask (`app.py`) | Local: `http://localhost:8080`. Production: set automatically in ECS task definition to your ALB URL |
| `AWS_ACCOUNT_ID` | Deploy scripts | `aws sts get-caller-identity --query Account --output text` |
| `AWS_REGION` | AWS CLI / Terraform | e.g. `us-east-1` (must match `infra/variables.tf`) |
| `AWS_ACCESS_KEY_ID` | AWS CLI | IAM user → Security credentials → Create access key |
| `AWS_SECRET_ACCESS_KEY` | AWS CLI | Same CSV download when key is created (shown once) |

AWS credentials are **not** stored in this repo. Use `aws configure` or environment variables; see [ROADMAP.md](./ROADMAP.md) for details.

## Tear down

```bash
cd infra
terraform destroy -var-file=terraform.tfvars
```

## Documentation

- **[ROADMAP.md](./ROADMAP.md)** — phased roadmap, why each file/line exists, local vs production, where every env value comes from
- **[plan.md](./plan.md)** — original detailed tutorial plan

## License

MIT (use freely for learning and projects).
