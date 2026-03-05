# Plan: AWS Deployment — Terraform, ECR, and GitHub Actions

**TL;DR:** Three coordinated changes across two repos. (1) Fix HCP Terraform Cloud's "plan-only" behavior by adding a GitHub Actions workflow to `parseon-infrastructure` that triggers remote applies via the HCP API token. (2) Fix the Dockerfile build bug and rewrite the existing `cd.yml` to push images to AWS ECR instead of GHCR, then force-deploy the ECS service. (3) Fix the CloudFront `https-only` origin policy that will cause 502s on first deploy since there's no ALB cert yet.

---

## Step 1 — Fix Terraform "plan only": Add workflow to `parseon-infrastructure`

Create `.github/workflows/terraform.yml` with two jobs:

- **`plan`** — triggers on PRs targeting `main`. Runs `terraform init` + `terraform plan` using `hashicorp/setup-terraform` with `TF_API_TOKEN` secret. Posts plan output as a PR comment.
- **`apply`** — triggers on push to `main`. Runs `terraform init` + `terraform apply -auto-approve`. Because HCP Terraform Cloud is the remote backend, both operations execute remotely inside HCP Terraform — `-auto-approve` tells it not to pause and wait for confirmation from the CLI side. Targets the `environments/dev` directory. Prod apply is a separate job gated by `workflow_dispatch` with an image tag input.

**Why it's "plan only" today:** Both environment workspaces use HCP Terraform Cloud as the remote backend (`terraform { cloud { organization = "maroonvillage-hcp-organization" ... } }`). By default, HCP Terraform workspaces require a manual "Confirm & Apply" click in the HCP UI after a plan — there's no bug in the Terraform code itself.

Required GitHub secret to add to the `parseon-infrastructure` repo:

- `TF_API_TOKEN` — a HCP Terraform user or team token from `app.terraform.io`

---

## Step 2 — Fix Dockerfile build bug

In `parseon-agentic-backend/Dockerfile`, the builder stage runs:

```dockerfile
RUN pip install -e ".[prod]"
```

But `pyproject.toml` defines only `[dev]` and `[test]` extras — there is **no `[prod]` extra**. This will error with `error: extras 'prod' not found` at build time.

**Fix:** Change to `pip install .` (installs base dependencies only).

Also verify that a `models/` directory exists at the repo root before the Docker build runs — the runtime stage has `COPY models/ /app/models/`. If it doesn't exist or contains large ML model files that shouldn't be baked into the image, remove that line and load models from S3 at startup instead.

---

## Step 3 — Update `cd.yml` to push to AWS ECR

Rewrite the Docker build/push portion of `.github/workflows/cd.yml` in `parseon-agentic-backend`:

- Replace the `docker/login-action` GHCR step with `aws-actions/configure-aws-credentials` + `aws-actions/amazon-ecr-login`
- Change the image tag base to `${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.us-east-1.amazonaws.com/parseon-api`
- Use two tags: `<sha>` (commit SHA for traceability) and `latest` (so dev ECS task using `ecr_image_tag = "latest"` picks it up automatically)
- Keep the existing `aws ecs update-service --force-new-deployment` block, guarded by `vars.DEPLOY_PLATFORM == 'aws'`

**Current gap:** `cd.yml` pushes to GHCR (`ghcr.io/${{ github.repository }}`), but the ECS task definition is configured to pull from AWS ECR (`<account>.dkr.ecr.us-east-1.amazonaws.com/parseon-api`). ECS uses an IAM execution role for ECR pull — no registry credentials to manage.

Required GitHub secrets/vars to add to `parseon-agentic-backend` repo:

| Name                            | Value                                                 |
| ------------------------------- | ----------------------------------------------------- |
| `secrets.AWS_ACCESS_KEY_ID`     | IAM user from bootstrap module                        |
| `secrets.AWS_SECRET_ACCESS_KEY` | IAM user from bootstrap module                        |
| `secrets.AWS_ACCOUNT_ID`        | 12-digit AWS account ID (for ECR URI)                 |
| `vars.DEPLOY_PLATFORM`          | `aws`                                                 |
| `vars.AWS_REGION`               | `us-east-1`                                           |
| `vars.ECS_CLUSTER_STAGING`      | `parseon-dev-cluster`                                 |
| `vars.ECS_SERVICE_STAGING`      | `parseon-dev-service` (confirm from Terraform output) |
| `vars.ECS_CLUSTER_PRODUCTION`   | `parseon-prod-cluster`                                |
| `vars.ECS_SERVICE_PRODUCTION`   | `parseon-prod-service`                                |

---

## Step 4 — Fix CloudFront `https-only` origin

In `modules/cloudfront/main.tf`, change:

```hcl
origin_protocol_policy = "https-only"
```

to:

```hcl
origin_protocol_policy = "http-only"
```

The ALB has no HTTPS listener until `alb_certificate_arn` is set in `terraform.tfvars`. CloudFront attempting HTTPS to the ALB on first deploy will cause 502s/504s. Once an ACM certificate is provisioned and the ARN is available, set `alb_certificate_arn` in `environments/dev/terraform.tfvars` and revert this to `https-only`.

---

## Step 5 — Handle prod `ecr_image_tag` placeholder

In `environments/prod/terraform.tfvars`:

```hcl
ecr_image_tag = "REPLACE_WITH_IMAGE_TAG"
```

This is a placeholder that will cause ECS to fail. For prod deploys, the GitHub Actions workflow should pass `-var="ecr_image_tag=<commit-sha>"` at apply time rather than hardcoding in tfvars. Add a `workflow_dispatch` input to the infrastructure workflow for the image tag so prod deploys are explicit and auditable.

---

## Step 6 — Environment variables (deferred)

The ECS task definition in `modules/ecs_service/main.tf` currently has no `environment` or `secrets` block — the container will start but any feature requiring DB/API keys will fail. This is deferred to a follow-up. When ready:

- Sensitive values (`OPENAI_API_KEY`, `DB_PASSWORD`, etc.) → AWS Secrets Manager, referenced via `secrets_arns` variable already accepted by the `iam` module
- Non-sensitive values (`STORAGE_TYPE`, `S3_BUCKET_NAME`, `AWS_REGION`, `CORS_ORIGINS`) → `environment` array in the task definition container spec
- `DATABASE_URL` → construct from RDS module output in `environments/dev/main.tf` and inject as a secret

---

## Verification Checklist

- [ ] Push to `parseon-infrastructure` `main` → Actions workflow triggers → confirms a "Run" appears in HCP Terraform UI and auto-applies
- [ ] Push to `parseon-agentic-backend` `main` → CD workflow logs into ECR, builds image without error, pushes successfully
- [ ] `aws ecs update-service` runs and ECS service cycles to a new task revision
- [ ] New ECS task reaches `RUNNING` state (check CloudWatch logs at `/ecs/parseon-dev`)
- [ ] `GET <alb-dns-or-cloudfront-url>/health` returns `{"status":"ok"}`

---

## Decisions Made

- HCP Terraform Cloud API token approach chosen over CLI-only apply — keeps remote state and audit log in HCP Terraform
- Image registry switched from GHCR to ECR — required for ECS IAM-based pull without registry credential management
- CloudFront set to `http-only` origin temporarily — avoids blocking first deploy; harden with ACM cert + `https-only` later
- ECS env vars/secrets deferred per user decision — container will start but DB/API features will be non-functional until follow-up

---

## Known Issues / Gaps Not Addressed Here

- `docker-compose.yml` missing — `make docker-dev` will fail (`docker-compose up --build` has no file to read)
- `DYNAMODB_TABLE_NAME=parseon-file-metadata` referenced in `.env.example` for cloud metadata mode — no DynamoDB module in Terraform
- No CI/CD for `parseon-web-ui` frontend — build/deploy is entirely manual
- CloudFront `origin_protocol_policy = "https-only"` should be reverted to `https-only` once ACM cert is in place
- RDS `deletion_protection = true` — cannot destroy RDS via `terraform destroy` without manually toggling this first
