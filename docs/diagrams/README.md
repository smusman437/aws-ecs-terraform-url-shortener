# Architecture diagrams

| File | Description |
|------|-------------|
| [01-request-sequence.png](./01-request-sequence.png) | HTTP request path: User → ALB → Target Group → ECS → Flask |
| [02-network-topology.png](./02-network-topology.png) | VPC, subnets (2 AZs), IGW, ECR, CloudWatch |
| [03-terraform-provision-flow.png](./03-terraform-provision-flow.png) | Order Terraform creates resources |
| [04-terraform-module-inputs.png](./04-terraform-module-inputs.png) | How `main.tf` wires networking + ECR → ECS module |
| [05-deploy-vs-redeploy.png](./05-deploy-vs-redeploy.png) | App-only vs infrastructure change workflows |

Used in [INFRASTRUCTURE.md](../INFRASTRUCTURE.md).
