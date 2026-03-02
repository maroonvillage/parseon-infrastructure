aws_region   = "us-east-1"
project_name = "parseon"
environment  = "prod"

# ── Networking ─────────────────────────────────────────────────────────────────
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

# ── Compute ────────────────────────────────────────────────────────────────────
container_image   = "REPLACE_WITH_ECR_URI/parseon-api:latest"
container_port    = 8000
ecs_cpu           = 1024
ecs_memory        = 2048
ecs_desired_count = 2

# ── Database ───────────────────────────────────────────────────────────────────
db_username = "parseon_admin"
# export TF_VAR_db_password="<your-password>"

# ── IAM ────────────────────────────────────────────────────────────────────────
secrets_arns        = []
enable_rds_iam_auth = false

# ── TLS / CDN ──────────────────────────────────────────────────────────────────
alb_certificate_arn        = "REPLACE_WITH_ACM_ALB_CERT_ARN"
cloudfront_certificate_arn = "REPLACE_WITH_ACM_CLOUDFRONT_CERT_ARN"
