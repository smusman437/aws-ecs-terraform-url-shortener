# AWS ECS + Terraform Deployment Plan
## Project: URL Shortener API

> A production-ready URL shortener where users submit a long URL and receive a short code.
> Example: POST /shorten → `{ "short_code": "xK9mP2", "original": "https://google.com" }`
> We deploy this real API across all 7 phases from local Docker to live AWS infrastructure.

---

## Third-Party Tools and How to Get Them

| Tool | Purpose | How to Install |
|---|---|---|
| Docker Desktop | Build and run containers locally | https://www.docker.com/products/docker-desktop |
| AWS Account (free tier) | Cloud infrastructure | https://aws.amazon.com/free |
| AWS CLI | Talk to AWS from the terminal | `pip install awscli` |
| Terraform | Write infrastructure as code | https://developer.hashicorp.com/terraform/install |
| Python 3.12+ | Run the Flask application | https://www.python.org/downloads |
| curl | Test API endpoints from the terminal | Built into Mac/Linux. Windows: https://curl.se |

---

## Phase 1 — Docker: Containerise the URL Shortener

### What we are building
A Flask API with 4 endpoints packaged inside a Docker image so it runs identically everywhere.

### Project structure
```
url-shortener/
├── app.py
├── requirements.txt
└── Dockerfile
```

### Step 1 — Write the Flask API

```python
# app.py
# -----------------------------------------------------------------------------
# This is the main application file.
# Flask is a lightweight Python web framework for creating HTTP endpoints.
# We use an in-memory dictionary to store URL mappings.
# In production you would replace this with Redis or PostgreSQL.
# -----------------------------------------------------------------------------

from flask import Flask, request, jsonify, redirect
import random
import string

app = Flask(__name__)  # create the Flask application instance

# In-memory store: { "abc123": "https://google.com" }
url_store = {}


def generate_code(length=6):
    """
    Generate a random 6-character alphanumeric short code.
    Example output: "xK9mP2"
    string.ascii_letters = a-z and A-Z
    string.digits = 0-9
    random.choices picks `length` characters randomly with replacement.
    """
    chars = string.ascii_letters + string.digits
    return "".join(random.choices(chars, k=length))


@app.route("/health", methods=["GET"])
def health():
    """
    Health check endpoint.
    The AWS Load Balancer calls this every 30 seconds to confirm the app is alive.
    Must return HTTP 200 or ECS will mark the container unhealthy and replace it.
    """
    return jsonify({"status": "ok"}), 200


@app.route("/shorten", methods=["POST"])
def shorten():
    """
    Accept a long URL and return a short code.
    Request body (JSON): { "url": "https://some-very-long-url.com" }
    Response (JSON):     { "short_code": "xK9mP2", "original": "https://..." }
    """
    data = request.get_json()

    # Validate input - return 400 Bad Request if no URL provided
    if not data or "url" not in data:
        return jsonify({"error": "Please provide a 'url' field"}), 400

    original_url = data["url"]

    # Generate a unique code (loop handles the extremely rare collision case)
    code = generate_code()
    while code in url_store:
        code = generate_code()

    url_store[code] = original_url

    return jsonify({
        "short_code": code,
        "original": original_url,
        "short_url": f"http://localhost:8080/{code}"
    }), 201


@app.route("/<code>", methods=["GET"])
def redirect_url(code):
    """
    Look up a short code and redirect to the original URL.
    Example: GET /xK9mP2 -> 302 redirect to https://some-very-long-url.com
    Returns 404 if the code does not exist in our store.
    """
    original = url_store.get(code)
    if not original:
        return jsonify({"error": "Short code not found"}), 404
    return redirect(original, code=302)


@app.route("/all", methods=["GET"])
def list_all():
    """
    Return all stored URL mappings as JSON.
    Useful for debugging and verifying your entries.
    You would remove or protect this endpoint in a real production app.
    """
    return jsonify(url_store), 200


# -----------------------------------------------------------------------------
# Entry point: run on host 0.0.0.0 (all network interfaces) port 8080.
# host="0.0.0.0" is critical for Docker. Without it the app only listens
# inside the container on 127.0.0.1 and cannot be reached from outside.
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
```

### Step 2 — Write requirements.txt

```
# requirements.txt
# -----------------------------------------------------------------------------
# Lists every Python package Docker will install inside the image.
# Pin exact versions so the build is reproducible weeks or months later.
# -----------------------------------------------------------------------------

flask==3.0.0
```

### Step 3 — Write the Dockerfile

```dockerfile
# Dockerfile
# -----------------------------------------------------------------------------
# This file is a recipe Docker reads top-to-bottom to build your image.
# Each instruction creates a cached layer. Docker reuses cached layers
# on subsequent builds if that layer's inputs have not changed.
# Strategy: put rarely-changing lines first, frequently-changing lines last.
# -----------------------------------------------------------------------------

# Start from the official Python 3.12 slim image.
# "slim" = minimum OS packages = smaller final image size (~50MB vs ~1GB).
FROM python:3.12-slim

# Set the working directory inside the container.
# All subsequent COPY, RUN, CMD commands operate from /app.
# Docker creates /app automatically if it does not exist.
WORKDIR /app

# Copy requirements.txt BEFORE copying the rest of the code.
# Why? If requirements.txt has not changed, Docker reuses the cached
# pip install layer and skips the expensive install step entirely.
COPY requirements.txt .

# Install Python packages.
# --no-cache-dir: do not save the pip cache inside the image (smaller size).
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code.
# This layer changes every time you edit app.py, so it comes last.
# If it were first, every code change would invalidate the pip install cache.
COPY . .

# Document that the container listens on port 8080.
# This does NOT open the port - it is metadata only.
# The actual port mapping happens with "docker run -p 8080:8080".
EXPOSE 8080

# The command Docker runs when a container starts from this image.
# List form ["python", "app.py"] is preferred over string form "python app.py"
# because the list form does not spawn a shell process in between.
CMD ["python", "app.py"]
```

### Step 4 — Build and run locally

```bash
# Navigate into the project folder
cd url-shortener/

# Build the Docker image
# -t url-shortener  : name (tag) the image "url-shortener"
# .                 : look for Dockerfile in the current directory
docker build -t url-shortener .

# Run the container
# -p 8080:8080  : map port 8080 on your laptop to port 8080 inside the container
# url-shortener : the image name we built above
docker run -p 8080:8080 url-shortener
```

### How to test Phase 1

```bash
# Open a second terminal. Leave the container running in the first terminal.

# Test 1: Health check - should return 200 OK
curl http://localhost:8080/health
# Expected: {"status": "ok"}

# Test 2: Shorten a long URL
curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.google.com"}'
# Expected: {"original": "https://www.google.com", "short_code": "xK9mP2", "short_url": "..."}

# Test 3: Use the short code to redirect (replace xK9mP2 with your actual code)
# -L flag tells curl to follow redirects
curl -L http://localhost:8080/xK9mP2
# Expected: redirects and returns the Google homepage HTML

# Test 4: List all stored URLs
curl http://localhost:8080/all
# Expected: {"xK9mP2": "https://www.google.com"}

# Test 5: Bad input - should return 400 error
curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{}'
# Expected: {"error": "Please provide a 'url' field"}
```

### Phase 1 checklist
- [ ] `docker build` completes with no errors
- [ ] `docker run` starts and shows "Running on http://0.0.0.0:8080"
- [ ] GET /health returns `{"status": "ok"}`
- [ ] POST /shorten returns a short_code
- [ ] GET /short_code redirects to the original URL

---

## Phase 2a — AWS: Account and CLI Setup

### What we are doing
Creating an AWS account, setting up a non-root IAM user, and confirming the AWS CLI works.

### Step 1 — Create AWS account
1. Go to https://aws.amazon.com/free
2. Click "Create a Free Account"
3. Enter email address and choose an account name
4. Enter credit card (free tier - you will not be charged for this roadmap)
5. Complete phone verification and identity check

### Step 2 — Create IAM user (never use root for CLI)

```
AWS Console -> IAM -> Users -> Create User
  Username:     terraform-user
  Access type:  Programmatic access (check this box)
  Permissions:  Attach policies directly -> AdministratorAccess

After creating: DOWNLOAD the CSV file containing the Access Key and Secret Key.
You cannot view the Secret Key again after closing this screen.
```

### Step 3 — Install and configure the AWS CLI

```bash
# Install
pip install awscli

# Configure with the keys from your downloaded CSV file
aws configure
#   AWS Access Key ID:     AKIA...   (from CSV)
#   AWS Secret Access Key: xxxxxxxx  (from CSV)
#   Default region name:   us-east-1
#   Default output format: json
```

### Step 4 — Verify connection

```bash
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAIOSFODNN7EXAMPLE",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/terraform-user"
# }
```

### The 6 AWS services you will use

```
IAM (Identity and Access Management)
  Controls who can do what on AWS.
  You will create a role that gives ECS permission to pull your Docker
  image from ECR and write logs to CloudWatch. Without this role,
  ECS cannot start your container.

VPC (Virtual Private Cloud)
  A private network that belongs only to your AWS account.
  Every resource you create (ECS tasks, load balancer) lives inside
  this network. Think of it as your own isolated data center.

Subnets
  Smaller address ranges inside your VPC.
  Public subnet  = has a route to the internet (load balancer goes here)
  Private subnet = no internet route (containers go here in production)
  We use two subnets in different availability zones so if one AWS
  data center has problems, your app keeps running in the other.

Security Groups
  Firewall rules attached to individual resources.
  ALB security group: allow port 80 from 0.0.0.0/0 (anyone on the internet)
  ECS security group: allow port 8080 from the ALB only (not from the internet)
  This enforces: users -> ALB -> containers. Users cannot hit containers directly.

ECR (Elastic Container Registry)
  AWS private Docker image storage.
  Like DockerHub but inside your AWS account.
  ECS pulls your url-shortener image from here at deploy time.

ECS (Elastic Container Service) with Fargate
  Runs your Docker container as a fully managed service.
  Fargate = you never manage, patch, or SSH into any server.
  You declare "run 2 copies with 256 CPU and 512MB RAM" and AWS handles the rest.
```

### Phase 2a checklist
- [ ] AWS free-tier account created
- [ ] IAM user created with AdministratorAccess policy
- [ ] Access Key CSV downloaded and stored safely
- [ ] `aws configure` completed successfully
- [ ] `aws sts get-caller-identity` returns your Account ID

---

## Phase 2b — Terraform: Infrastructure as Code

### What we are doing
Installing Terraform and using it to create the ECR repository for our Docker image.

### Why Terraform instead of clicking in the AWS console?
Clicking creates resources you cannot reproduce. Terraform is code — you commit it
to git, a teammate can run it, and you can recreate your entire infrastructure in minutes.
Every change is tracked, reviewable, and reversible.

### Step 1 — Install Terraform

```bash
# Mac
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Windows: download installer from https://developer.hashicorp.com/terraform/install

# Verify installation
terraform --version
# Expected: Terraform v1.7.x or higher
```

### Step 2 — Create the infra/ folder

```
url-shortener/
├── app.py
├── requirements.txt
├── Dockerfile
└── infra/           <- create this folder
    └── main.tf      <- create this file
```

### Step 3 — Write main.tf

```hcl
# infra/main.tf
# -----------------------------------------------------------------------------
# This file tells Terraform:
#   1. Which cloud provider to use (AWS)
#   2. Which region to deploy into
#   3. What resources to create (ECR repository)
# -----------------------------------------------------------------------------

# terraform block: declares which providers (plugins) we need.
# Terraform downloads the AWS provider from the Hashicorp public registry.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # use any version in the 5.x range
    }
  }
}

# provider block: configures the AWS provider.
# Terraform reads your AWS credentials from ~/.aws/credentials automatically
# (set up by aws configure in Phase 2a).
provider "aws" {
  region = "us-east-1"
}

# resource block: creates an ECR repository named "url-shortener" on AWS.
# "aws_ecr_repository" is the resource type from the AWS provider.
# "url_shortener" is our local reference name used to connect resources.
resource "aws_ecr_repository" "url_shortener" {
  name = "url-shortener"

  # MUTABLE: allows pushing new images with the same tag (e.g. "latest").
  # IMMUTABLE: prevents overwriting existing tags - stricter for production.
  image_tag_mutability = "MUTABLE"

  tags = {
    Project     = "url-shortener"
    Environment = "production"
  }
}

# output block: prints the ECR URI after terraform apply completes.
# We need this URI in Phase 3 to push our Docker image.
output "ecr_uri" {
  value       = aws_ecr_repository.url_shortener.repository_url
  description = "Use this URI to push your Docker image in Phase 3"
}
```

### Step 4 — Run the 4 Terraform commands

```bash
cd infra/

# COMMAND 1: terraform init
# Downloads the AWS provider plugin into .terraform/ folder.
# Run once when you first create a project.
# Run again if you add a new provider.
terraform init
# Expected: "Terraform has been successfully initialized!"


# COMMAND 2: terraform plan
# Reads your .tf files, connects to AWS, calculates what would change.
# NOTHING is created yet. This is a safe dry run.
terraform plan
# Expected: "Plan: 1 to add, 0 to change, 0 to destroy."


# COMMAND 3: terraform apply
# Actually creates the resources on AWS.
# Always review the plan output before typing "yes".
terraform apply
# Type "yes" when prompted.
# Expected output:
# aws_ecr_repository.url_shortener: Creating...
# aws_ecr_repository.url_shortener: Creation complete
# Outputs:
# ecr_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/url-shortener"
# SAVE THIS URI - needed in Phase 3.


# COMMAND 4: terraform destroy
# Deletes everything Terraform created.
# Use when you are done learning to avoid unexpected AWS charges.
# terraform destroy
```

### How to test Phase 2b

```bash
# Verify the ECR repository was created
aws ecr describe-repositories --region us-east-1
# Expected: JSON showing "repositoryName": "url-shortener"

# Check that Terraform state file was created
ls -la infra/
# Expected: terraform.tfstate file exists (this tracks what Terraform created)
```

### Phase 2b checklist
- [ ] `terraform --version` returns a version number
- [ ] `terraform init` shows "successfully initialized"
- [ ] `terraform plan` shows "1 to add"
- [ ] `terraform apply` completes successfully
- [ ] ECR repo visible in AWS Console -> ECR -> Repositories
- [ ] `terraform.tfstate` file exists in infra/

---

## Phase 3 — Push Image: Get Docker Image into ECR

### What we are doing
Authenticating Docker to our ECR registry, tagging the local image with the ECR URI,
and pushing it so AWS can pull and run it.

### Why this step exists
ECS cannot access images on your laptop. It pulls from ECR — a registry inside your
AWS account. Pushing to ECR is the bridge between local development and AWS deployment.
Every new version of your app goes through this same 3-step process.

### Step 1 — Set environment variables

```bash
# Replace 123456789012 with YOUR actual Account ID (from aws sts get-caller-identity)
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
export ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/url-shortener
```

### Step 2 — Authenticate Docker to ECR

```bash
# aws ecr get-login-password: calls AWS API and returns a temporary 12-hour password.
# The | (pipe) sends that password directly into docker login.
# docker login stores credentials so Docker can push to this registry.
# --username AWS is always literally "AWS" for ECR (not your IAM username).
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Expected: Login Succeeded
```

### Step 3 — Tag and push the image

```bash
# docker tag: creates a second name pointing to the same local image.
# Your original "url-shortener:latest" still exists unchanged.
# The new name (ECR_URI:latest) tells Docker which registry to push to.
docker tag url-shortener:latest $ECR_URI:latest

# docker push: uploads each image layer to ECR.
# Docker images are made of layers (each Dockerfile instruction = 1 layer).
# Only layers that do not already exist in ECR are uploaded.
# First push takes about 1 minute. Later pushes (code changes only) are faster
# because base layers (Python runtime, pip packages) are already cached in ECR.
docker push $ECR_URI:latest

# Expected output:
# 3b1f7d3a45dc: Pushed
# latest: digest: sha256:abc123... size: 52345678
```

### How to test Phase 3

```bash
# Verify the image exists in ECR
aws ecr list-images \
  --repository-name url-shortener \
  --region $AWS_REGION

# Expected:
# { "imageIds": [{ "imageTag": "latest", "imageDigest": "sha256:abc123..." }] }
```

### Phase 3 checklist
- [ ] `docker login` to ECR returns "Login Succeeded"
- [ ] `docker tag` completes silently (no output is correct)
- [ ] `docker push` uploads layers and shows a digest
- [ ] AWS Console -> ECR -> url-shortener -> Images shows "latest" tag

---

## Phase 4 — ECS Deploy: Full Terraform Deployment

### What we are building
The complete AWS infrastructure to run the URL Shortener API on the internet:
VPC -> Subnets -> Security Groups -> ECS Cluster -> Task Definition -> ECS Service -> ALB -> Public URL

### Step 1 — Create networking.tf

```hcl
# infra/networking.tf
# -----------------------------------------------------------------------------
# Creates the network all other resources live inside.
# Think of this as building roads before placing buildings.
# -----------------------------------------------------------------------------

# VPC: our isolated private network in AWS.
# cidr_block = "10.0.0.0/16" gives us IP range 10.0.0.0 -> 10.0.255.255
# enable_dns_hostnames: lets resources inside resolve DNS names.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "url-shortener-vpc" }
}

# Public subnet in availability zone us-east-1a.
# map_public_ip_on_launch: resources placed here automatically get a public IP.
# This is where our load balancer will live.
resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "url-shortener-pub-a" }
}

# Second public subnet in availability zone us-east-1b.
# Two AZs = high availability. If us-east-1a has problems,
# traffic automatically flows through us-east-1b.
resource "aws_subnet" "pub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "url-shortener-pub-b" }
}

# Internet Gateway: connects the VPC to the public internet.
# Without this, nothing in our VPC can reach or be reached from outside.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "url-shortener-igw" }
}

# Route table: directs traffic from subnets.
# Rule: send all traffic (0.0.0.0/0 = everywhere) to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "url-shortener-rt" }
}

# Associate the route table with both subnets.
# Without this association the subnets do not use the route and cannot reach the internet.
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.public.id
}
```

### Step 2 — Create ecs.tf

```hcl
# infra/ecs.tf
# -----------------------------------------------------------------------------
# Creates the ECS cluster, task definition, service, security groups, and ALB.
# This file is the heart of the deployment.
# -----------------------------------------------------------------------------

# ECS Cluster: a logical container for ECS services and tasks.
# With Fargate there are no EC2 instances to manage inside the cluster.
resource "aws_ecs_cluster" "main" {
  name = "url-shortener-cluster"
}

# IAM Role for ECS task execution.
# ECS needs permission to:
#   1. Pull the Docker image from ECR
#   2. Write container stdout/stderr to CloudWatch Logs
# assume_role_policy: declares that ECS tasks (ecs-tasks.amazonaws.com) can use this role.
resource "aws_iam_role" "ecs_exec" {
  name = "url-shortener-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Attach the AWS-managed policy that grants ECR pull and CloudWatch write access.
# AmazonECSTaskExecutionRolePolicy is a standard policy AWS provides for this purpose.
resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch Log Group: all container output (print statements, errors) goes here.
# retention_in_days = 7: logs are deleted automatically after 7 days to control cost.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/url-shortener"
  retention_in_days = 7
}

# Task Definition: blueprint for how to run our container.
# cpu = "256"   = 0.25 vCPU  (smallest option, fine for learning)
# memory = "512" = 512 MB RAM
# network_mode = "awsvpc": required for Fargate - each task gets its own network interface.
resource "aws_ecs_task_definition" "app" {
  family                   = "url-shortener"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec.arn

  # JSON string describing every container in this task.
  # We run one container: our url-shortener image from ECR.
  container_definitions = jsonencode([{
    name  = "url-shortener"
    image = "${aws_ecr_repository.url_shortener.repository_url}:latest"

    # Expose container port 8080 (where our Flask app listens).
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    # Direct all stdout and stderr from the container to CloudWatch Logs.
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/url-shortener"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# Security Group for the Application Load Balancer.
# Allow port 80 HTTP from anyone on the internet (0.0.0.0/0).
# Allow all outbound traffic so the ALB can forward requests to containers.
resource "aws_security_group" "alb" {
  name   = "url-shortener-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for ECS containers.
# Allow port 8080 ONLY from the ALB security group.
# Users cannot reach containers directly - they must go through the ALB.
resource "aws_security_group" "ecs" {
  name   = "url-shortener-ecs-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer.
# internal = false: internet-facing, reachable from outside AWS.
# Gives us a public DNS name like: url-shortener-alb-xxx.us-east-1.elb.amazonaws.com
resource "aws_lb" "main" {
  name               = "url-shortener-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
}

# Target Group: tells the ALB where to send traffic.
# target_type = "ip": required for Fargate (Fargate assigns IPs not EC2 instance IDs).
# health_check: ALB pings GET /health every 30 seconds.
# 3 consecutive failures -> container marked unhealthy -> ECS replaces it.
resource "aws_lb_target_group" "app" {
  name        = "url-shortener-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Listener: the ALB listens on port 80 and forwards all requests to the target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS Service: ensures desired_count = 2 copies of the task ALWAYS run.
# If one container crashes, ECS automatically starts a replacement.
# depends_on = [aws_lb_listener.http]: ensures the listener exists before the service
# registers with the target group (prevents a timing error during first deploy).
resource "aws_ecs_service" "app" {
  name            = "url-shortener-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true  # Fargate tasks need a public IP to pull from ECR
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "url-shortener"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}

# Print the public URL of the deployed app after terraform apply.
output "api_url" {
  value       = "http://${aws_lb.main.dns_name}"
  description = "Public URL of your URL Shortener API"
}
```

### Step 3 — Deploy

```bash
cd infra/

terraform plan   # review: approximately 18 resources
terraform apply  # type "yes" - takes 3-5 minutes

# Final output:
# api_url = "http://url-shortener-alb-xxxx.us-east-1.elb.amazonaws.com"
```

### How to test Phase 4

```bash
# Replace with your actual ALB URL from the terraform output
ALB_URL="http://url-shortener-alb-xxxx.us-east-1.elb.amazonaws.com"

# Test 1: Health check
curl $ALB_URL/health
# Expected: {"status": "ok"}

# Test 2: Shorten a URL
curl -X POST $ALB_URL/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.github.com"}'
# Expected: {"original": "https://www.github.com", "short_code": "xK9mP2", ...}

# Test 3: Follow redirect
curl -L $ALB_URL/xK9mP2
# Expected: redirects and returns the GitHub homepage
```

### Phase 4 checklist
- [ ] `terraform apply` completes with no errors
- [ ] `api_url` output printed in terminal
- [ ] GET /health returns `{"status": "ok"}` from the ALB URL
- [ ] POST /shorten returns a short_code
- [ ] ECS Console shows 2 running tasks

---

## Phase 5a — Production: Auto-scaling, Alarms, Secrets

### Step 1 — Auto-scaling

```hcl
# infra/autoscaling.tf
# -----------------------------------------------------------------------------
# Auto-scaling watches CPU usage and adjusts running container count automatically.
# High CPU -> ECS starts more containers.
# CPU returns to normal -> ECS removes the extras.
# -----------------------------------------------------------------------------

# Register the ECS service as a scalable target.
# min_capacity = 2: never fewer than 2 containers (ensures availability)
# max_capacity = 10: never more than 10 (controls cost ceiling)
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scaling policy: keep average CPU near 70%.
# Above 70% -> add containers (scale_out_cooldown: wait 60s before adding again)
# Below 70% -> remove containers (scale_in_cooldown: wait 300s before removing)
# Longer scale-in cooldown prevents removing containers too aggressively.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "url-shortener-cpu-scale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
```

### Step 2 — CloudWatch Alarm for task failures

```hcl
# infra/alarms.tf
# -----------------------------------------------------------------------------
# This alarm fires whenever an ECS task fails to start.
# In production you would connect this to an SNS topic to send email alerts.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "task_failures" {
  alarm_name          = "url-shortener-task-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60       # check every 60 seconds
  statistic           = "Sum"
  threshold           = 0        # alarm if even 1 task fails
  alarm_description   = "ECS tasks are failing. Check CloudWatch logs."

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}
```

### Step 3 — View container logs from the terminal

```bash
# Stream live logs (press Ctrl+C to stop)
aws logs tail /ecs/url-shortener --follow --region us-east-1

# Get logs from the last 30 minutes
aws logs filter-log-events \
  --log-group-name /ecs/url-shortener \
  --region us-east-1
```

### Phase 5a checklist
- [ ] `terraform apply` with autoscaling.tf and alarms.tf succeeds
- [ ] ECS Console -> service -> Configuration shows auto-scaling min 2 / max 10
- [ ] Stop one task manually - ECS replaces it within 30 seconds
- [ ] CloudWatch -> Alarms shows `url-shortener-task-failures`

---

## Phase 5b — Modules and Remote State

### What we are doing
Moving the Terraform state file from your laptop to S3, and splitting Terraform into
reusable modules so the code is maintainable and team-ready.

### Why remote state matters
The state file currently exists only on your laptop. If your laptop is lost, you lose the
ability to manage your infrastructure. If a teammate runs terraform apply at the same time
you do, the state gets corrupted. S3 remote state and DynamoDB locking solve both problems.

### Step 1 — Create S3 bucket and DynamoDB table (one-time)

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket url-shortener-terraform-state \
  --region us-east-1

# Enable versioning: lets you recover previous state if something goes wrong
aws s3api put-bucket-versioning \
  --bucket url-shortener-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
# When someone runs terraform apply, Terraform writes a lock to this table.
# A second person who runs apply at the same time will see the lock and wait.
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 2 — Add backend block to main.tf

```hcl
# infra/main.tf - add the backend block inside the terraform {} block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend block: tells Terraform to store state in S3 instead of locally.
  # After adding this, run "terraform init" again.
  # Terraform will ask: "Copy existing state to new backend?" - type "yes".
  backend "s3" {
    bucket         = "url-shortener-terraform-state"
    key            = "url-shortener/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true  # encrypt state at rest in S3
  }
}
```

### Step 3 — Final folder structure with modules

```
url-shortener/
├── app.py
├── requirements.txt
├── Dockerfile
└── infra/
    ├── main.tf              <- backend block + module calls
    ├── variables.tf         <- input variable declarations
    ├── terraform.tfvars     <- dev values (add to .gitignore)
    ├── prod.tfvars          <- prod values
    └── modules/
        ├── networking/
        │   ├── main.tf      <- VPC, subnets, IGW, route tables
        │   ├── variables.tf <- input: env (dev or prod)
        │   └── outputs.tf   <- output: vpc_id, public_subnet_ids
        └── ecs/
            ├── main.tf      <- cluster, task def, service, ALB
            ├── variables.tf <- input: image_uri, desired_count, vpc_id
            └── outputs.tf   <- output: api_url
```

### Step 4 — Use workspaces for dev and prod

```bash
# Migrate local state to S3 (run after adding the backend block)
terraform init
# Type "yes" when asked to copy existing state

# Create separate workspaces
terraform workspace new dev
terraform workspace new prod

# Deploy to dev environment
terraform workspace select dev
terraform apply -var-file="terraform.tfvars"

# Deploy to prod environment (desired_count = 3 for prod, 1 for dev)
terraform workspace select prod
terraform apply -var-file="prod.tfvars"

# Verify state is now in S3
aws s3 ls s3://url-shortener-terraform-state/url-shortener/
# Expected: terraform.tfstate file listed
```

### Phase 5b checklist
- [ ] S3 bucket created with versioning enabled
- [ ] DynamoDB table created
- [ ] `terraform init` migrates state to S3 successfully
- [ ] `terraform workspace list` shows both dev and prod
- [ ] `aws s3 ls` confirms state file exists in S3

---

## Quick Reference — All Commands

```bash
# DOCKER
docker build -t url-shortener .
docker run -p 8080:8080 url-shortener
docker tag url-shortener:latest $ECR_URI:latest
docker push $ECR_URI:latest

# AWS CLI
aws sts get-caller-identity
aws ecr describe-repositories
aws ecr list-images --repository-name url-shortener
aws logs tail /ecs/url-shortener --follow

# TERRAFORM
terraform init
terraform plan
terraform apply
terraform destroy
terraform workspace new dev
terraform workspace select prod
terraform output

# TEST API (replace YOUR_URL with localhost:8080 or your ALB URL)
curl http://YOUR_URL/health
curl -X POST http://YOUR_URL/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com"}'
curl -L http://YOUR_URL/SHORT_CODE
```

---

*Work through each phase in order. Each one builds on the previous. Complete the checklist before moving forward.*
