# Production (prod) — Ready for Testing

Prod uses the **same AWS resources** as dev (one ECS cluster, one ALB).  
`prod.tfvars` changes **how** they run: more tasks + auto-scaling.

| Setting | dev (`terraform.tfvars`) | prod (`prod.tfvars`) |
|---------|--------------------------|----------------------|
| `desired_count` | 1 | 2 |
| `enable_autoscaling` | false | true |
| `autoscaling_min` / `max` | — | 2 / 10 |
| `environment` tag | dev | prod |

---

## When you are ready to test prod

```bash
export AWS_PROFILE=terraform-user

# 1. Preview prod infra changes (no apply)
./scripts/plan.sh prod

# 2. Full prod deploy (plan → you type yes → apply → image → ECS)
./scripts/deploy.sh prod

# 3. Check health
./scripts/status.sh
./scripts/test-api.sh

# 4. After app-only changes (no .tf edits)
./scripts/redeploy-app.sh prod
```

---

## What prod deploy changes on AWS

- ECS runs **2 tasks** instead of 1 (high availability)
- Auto-scaling adds tasks up to **10** when CPU > ~70%
- Resource tags show `Environment = prod`

---

## Switch back to dev settings

```bash
./scripts/plan.sh dev
./scripts/deploy.sh dev
```

That sets `desired_count = 1` and turns off autoscaling.

---

## Tear down (same as dev)

```bash
./scripts/destroy.sh prod
# or
./scripts/destroy.sh dev
```

Both target the same infrastructure stack.

---

## CI / non-interactive prod deploy

```bash
AUTO_APPROVE=1 ./scripts/deploy.sh prod
```

Still runs **plan** first, then apply without asking `yes`.
