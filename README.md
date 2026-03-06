# parseon-infrastructure

Terraform infrastructure-as-code for the Parseon platform, deployed to AWS via [HCP Terraform](https://app.terraform.io) (formerly Terraform Cloud). GitHub Actions drives plan and apply operations remotely so that state, audit logs, and run history live in HCP Terraform.

---

## Architecture

| Layer | AWS Service |
|-------|-------------|
| Networking | VPC, public + private subnets, IGW, NAT Gateway |
| Compute | ECS Fargate cluster + service, App Auto Scaling |
| Container registry | ECR |
| Database | RDS (PostgreSQL) |
| Load balancing | ALB (HTTP; HTTPS once ACM cert is ready) |
| CDN | CloudFront |
| Storage | S3 |
| Messaging | SQS |
| IAM | ECS task role, execution role |

State for `dev` and `prod` is stored remotely in HCP Terraform workspaces (`parseon-agentic-dev` and `parseon-agentic-prod`) under the `maroonvillage-hcp-organization` organization.

---

## Repository layout

```
.
├── bootstrap/            # One-time IAM bootstrap (local state, run manually)
├── environments/
│   ├── dev/              # Dev environment root module (HCP remote backend)
│   └── prod/             # Prod environment root module (HCP remote backend)
├── modules/              # Reusable Terraform modules
│   ├── alb/
│   ├── cloudfront/
│   ├── ecr/
│   ├── ecs_cluster/
│   ├── ecs_service/
│   ├── iam/
│   ├── rds/
│   ├── s3/
│   ├── security_groups/
│   ├── sqs/
│   ├── terraform_iam/    # Used by bootstrap only
│   └── vpc/
└── versions.tf           # Root-level provider version constraints
```

---

## One-time setup

### 1 — Bootstrap IAM (run once, from your workstation)

The `bootstrap/` directory creates the IAM group, policy, and operator user that HCP Terraform uses to call AWS APIs.

```bash
# Prerequisites: AWS CLI configured with AdministratorAccess
aws configure --profile parseon-bootstrap

cd bootstrap/
terraform init
terraform apply -var="existing_user_name=<your-iam-username>"
```

After `apply` succeeds:
- Detach `AdministratorAccess` from the user.
- Create an **Access Key** for the user (AWS Console → IAM → Users → Security credentials).
- The state file (`bootstrap/terraform.tfstate`) contains IAM resource IDs — store it safely (e.g. encrypted S3 or 1Password) and **do not commit it**.

### 2 — Configure HCP Terraform workspaces

In [app.terraform.io](https://app.terraform.io), for **both** `parseon-agentic-dev` and `parseon-agentic-prod` workspaces:

1. Set **Execution Mode** → **Remote**.
2. **Do not** connect the workspace to a VCS repository. The CI/CD pipeline uses the [API-driven workflow](https://developer.hashicorp.com/terraform/cloud-docs/run/api) (`hashicorp/tfc-workflows-github` actions) to upload configurations and trigger runs. Attaching a VCS connection blocks CLI/API-triggered applies.
3. Add the following **Environment Variables** (mark as sensitive):

   | Variable | Value |
   |----------|-------|
   | `AWS_ACCESS_KEY_ID` | Access key ID from step 1 |
   | `AWS_SECRET_ACCESS_KEY` | Secret access key from step 1 |

3. Add the following **Terraform Variables** (mark `db_password` as sensitive):

   | Variable | Value |
   |----------|-------|
   | `db_password` | RDS master password of your choice |

### 3 — Add the GitHub Actions secret

In **this** GitHub repository → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret name | Value |
|-------------|-------|
| `TF_API_TOKEN` | A HCP Terraform [user or team token](https://app.terraform.io/app/settings/tokens) |

---

## CI/CD workflow (`.github/workflows/terraform.yml`)

| Trigger | Job | Action |
|---------|-----|--------|
| Pull request → `main` | `plan` | Runs `terraform plan` in `environments/dev`, posts output as a PR comment |
| Push to `main` | `apply-dev` | Uploads `environments/dev` to HCP Terraform and triggers a run via API; posts run link to the merged PR |
| `workflow_dispatch` with `environment=prod` | `apply-prod` | Uploads `environments/prod` (with the supplied `ecr_image_tag`) to HCP Terraform and triggers a run via API |

Apply jobs use the `hashicorp/tfc-workflows-github` actions (`upload-configuration` → `create-run` → `apply-run`) so that runs are API-driven and not blocked by the workspace's VCS-connection setting.

---

## Deploying to prod

Prod applies are manual and gated by `workflow_dispatch`:

1. GitHub → Actions → **Terraform** → **Run workflow**.
2. Set **Target environment** → `prod`.
3. Set **ECR image tag** to the commit SHA or tag built by the `parseon-agentic-backend` CD pipeline (e.g. `a1b2c3d`).
4. Click **Run workflow**.

> The `ecr_image_tag` input overrides the placeholder in `environments/prod/terraform.tfvars` at apply time.

---

## Local development

```bash
# Init dev environment (connects to HCP Terraform; requires TF_TOKEN_app_terraform_io env var)
export TF_TOKEN_app_terraform_io="<your-hcp-terraform-token>"
cd environments/dev
terraform init
terraform plan
```

---

## TLS / HTTPS hardening (deferred)

`CloudFront → ALB` traffic currently uses HTTP (`origin_protocol_policy = "http-only"`) because the ALB has no HTTPS listener until an ACM certificate is provisioned. Once a certificate exists:

1. Add the ARNs to `environments/dev/terraform.tfvars`:
   ```hcl
   # ALB certificate must be in the same region as the ALB (us-east-1)
   alb_certificate_arn        = "arn:aws:acm:us-east-1:<account>:certificate/<alb-cert-id>"
   # CloudFront certificate MUST be in us-east-1 regardless of ALB region
   cloudfront_certificate_arn = "arn:aws:acm:us-east-1:<account>:certificate/<cf-cert-id>"
   ```
2. Change `origin_protocol_policy` in `modules/cloudfront/main.tf` from `"http-only"` to `"https-only"`.
3. Open a PR — the plan job will show the change, merging will auto-apply to dev.
