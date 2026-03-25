aws_region   = "us-east-1"
project_name = "parseon"
environment  = "prod"

# ── Networking ─────────────────────────────────────────────────────────────────
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

# ── Compute ────────────────────────────────────────────────────────────────────
ecr_image_tag     = "REPLACE_WITH_IMAGE_TAG"
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
# ── GitHub Actions OIDC ─────────────────────────────────────────────────────────────
github_repository          = "maroonvillage/parseon-agentic-backend"
frontend_github_repository = "maroonvillage/parseon-web-ui"
# ── TLS / CDN ──────────────────────────────────────────────────────────────────
# Real ACM ARNs required in prod before applying
alb_certificate_arn        = null
cloudfront_certificate_arn = null
