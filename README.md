# URL Shortener API

Flask URL shortener deployed on **AWS ECS Fargate** with **Terraform**, **ECR**, and an **Application Load Balancer**.

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check (ALB) |
| `POST` | `/shorten` | Create short code (`{"url":"..."}`) |
| `GET` | `/{code}` | Redirect to original URL |
| `GET` | `/apidocs` | Swagger UI |

## Prerequisites

- Docker, AWS CLI, Terraform 1.7+ (`darwin_arm64` on Apple Silicon)
- IAM user with deploy permissions (e.g. `terraform-user`)
- `aws configure --profile terraform-user`

## Quick start

```bash
export AWS_PROFILE=terraform-user

./scripts/local.sh                 # http://localhost:8080
./scripts/plan.sh dev              # preview infra changes
./scripts/deploy.sh dev            # deploy to AWS
./scripts/redeploy-app.sh dev      # app-only update
./scripts/test-api.sh              # smoke tests
./scripts/destroy.sh dev           # tear down AWS resources
```

**Swagger:** `http://localhost:8080/apidocs` (local) or `http://<alb-dns>/apidocs` (live)

## Repository layout

```
├── app.py, Dockerfile, requirements.txt
├── scripts/              # deploy, destroy, redeploy, plan, test
├── infra/                # Terraform (VPC, ECS, ALB, ECR)
│   ├── main.tf
│   └── modules/{networking,ecs}/
└── docs/                 # guides, diagrams, architecture
    └── diagrams/         # architecture PNGs
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md) | VPC, subnets, traffic flow, Terraform wiring |
| [docs/GUIDE.md](docs/GUIDE.md) | Full deployment guide |
| [docs/TERRAFORM.md](docs/TERRAFORM.md) | Terraform commands and file reference |
| [docs/PROD.md](docs/PROD.md) | Production deployment |

## Environment variables

| Variable | Purpose |
|----------|---------|
| `BASE_URL` | Set in ECS for `short_url` in API responses |
| `AWS_PROFILE` | `terraform-user` (or your deploy profile) |
| `AWS_ACCOUNT_ID` | Used by deploy scripts for ECR |

See [.env.example](.env.example). Do not commit secrets or `terraform.tfstate`.

## License

MIT
