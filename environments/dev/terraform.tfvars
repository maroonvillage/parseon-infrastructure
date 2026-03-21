aws_region   = "us-east-1"
project_name = "parseon"
environment  = "dev"

# ── Networking ─────────────────────────────────────────────────────────────────
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# ── Compute ────────────────────────────────────────────────────────────────────
# Replace with your real ECR image URI once the ECR repo exists.
ecr_image_tag     = "latest"
container_port    = 8000
ecs_cpu           = 512
ecs_memory        = 1024
ecs_desired_count = 1

# ── Database ───────────────────────────────────────────────────────────────────
db_username = "parseon_admin"
# db_password is intentionally omitted — set it via the environment variable:
#   export TF_VAR_db_password="<your-password>"

# ── IAM ────────────────────────────────────────────────────────────────────────
secrets_arns        = [] # e.g. ["arn:aws:secretsmanager:us-east-1:123456789012:secret/parseon/dev/db-abc123"]
enable_rds_iam_auth = false

# ── GitHub Actions OIDC ────────────────────────────────────────────────────────
# Must match the exact GitHub 'owner/repository' path.
# Example: "coleparsons/parseon-agentic-backend"
github_repository           = "coleparsons/parseon-agentic-backend"
create_github_oidc_provider = true # Set to false if provider already exists in this account

# ── TLS / CDN ──────────────────────────────────────────────────────────────────
# Both ARNs must be created in ACM before applying. CloudFront cert MUST be in us-east-1.
# Leave null until ACM certificates are provisioned for your domain
alb_certificate_arn        = null
cloudfront_certificate_arn = null
