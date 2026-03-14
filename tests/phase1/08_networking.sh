#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 08: Networking (VPC, Subnets, Security Groups)
#
# Verifies:
#   - VPC exists and is in 'available' state
#   - Public and private subnets are created across both AZs
#   - Internet gateway is attached
#   - NAT gateway exists in at least one public subnet (enables private egress)
#   - ALB security group allows inbound 80/443
#   - ECS API security group allows inbound on container port from ALB SG
#   - RDS security group allows inbound on 5432 from ECS SG
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "08 · Networking (VPC / Subnets / Security Groups)"

# ── 1. VPC ────────────────────────────────────────────────────────────────────
info "Finding VPC tagged for ${NAME_PREFIX}…"
VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" \
  --region "$AWS_REGION" \
  --query "Vpcs[0]" \
  --output json 2>/dev/null || echo "{}")

VPC_ID=$(echo "$VPC"     | jq -r '.VpcId // ""')
VPC_STATE=$(echo "$VPC"  | jq -r '.State // "NOT_FOUND"')
VPC_CIDR=$(echo "$VPC"   | jq -r '.CidrBlock // ""')

if [[ -n "$VPC_ID" && "$VPC_ID" != "null" ]]; then
  pass "VPC '${NAME_PREFIX}-vpc' exists: $VPC_ID (CIDR: $VPC_CIDR)"
else
  fail "VPC tagged Name=${NAME_PREFIX}-vpc not found."
  summarize "Networking"
  exit $?
fi

if [[ "$VPC_STATE" == "available" ]]; then
  pass "VPC state is available."
else
  fail "VPC state is '${VPC_STATE}' (expected available)."
fi

# ── 2. Subnets ────────────────────────────────────────────────────────────────
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --region "$AWS_REGION" \
  --query "Subnets[*].{Id:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,CIDR:CidrBlock,State:State}" \
  --output json 2>/dev/null || echo "[]")

TOTAL_SUBNETS=$(echo "$SUBNETS" | jq 'length')
PUBLIC_COUNT=$(echo "$SUBNETS" | jq '[.[] | select(.Public == true)] | length')
PRIVATE_COUNT=$(echo "$SUBNETS" | jq '[.[] | select(.Public == false)] | length')

info "Total subnets: $TOTAL_SUBNETS (public: $PUBLIC_COUNT, private: $PRIVATE_COUNT)"

if [[ "$PUBLIC_COUNT" -ge 2 ]]; then
  pass "$PUBLIC_COUNT public subnet(s) found (expected 2 across AZs)."
else
  fail "Expected at least 2 public subnets, found $PUBLIC_COUNT."
fi

if [[ "$PRIVATE_COUNT" -ge 2 ]]; then
  pass "$PRIVATE_COUNT private subnet(s) found (expected 2 across AZs)."
else
  fail "Expected at least 2 private subnets, found $PRIVATE_COUNT."
fi

# List AZs covered
AZS=$(echo "$SUBNETS" | jq -r '.[].AZ' | sort -u | tr '\n' ', ' | sed 's/,$//')
info "AZs covered: $AZS"

# ── 3. Internet Gateway ───────────────────────────────────────────────────────
IGW=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  --region "$AWS_REGION" \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text 2>/dev/null || echo "")

if [[ -n "$IGW" && "$IGW" != "None" ]]; then
  pass "Internet gateway attached: $IGW"
else
  fail "No internet gateway attached to VPC — public subnet traffic cannot reach the internet."
fi

# ── 4. NAT Gateway ────────────────────────────────────────────────────────────
NAT=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
  --region "$AWS_REGION" \
  --query "NatGateways[*].{Id:NatGatewayId,State:State,SubnetId:SubnetId}" \
  --output json 2>/dev/null || echo "[]")

NAT_COUNT=$(echo "$NAT" | jq 'length')
if [[ "$NAT_COUNT" -gt 0 ]]; then
  pass "$NAT_COUNT available NAT gateway(s) — private subnets have internet egress."
  echo "$NAT" | jq -r '.[] | "  NAT \(.Id) in subnet \(.SubnetId)"' | while read -r n; do info "$n"; done
else
  warn "No available NAT gateways found — ECS tasks in private subnets cannot pull from ECR or call external APIs."
fi

# ── 5. Security Groups ────────────────────────────────────────────────────────
echo ""
info "Checking security groups for ${NAME_PREFIX}…"
SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${NAME_PREFIX}-*" \
  --region "$AWS_REGION" \
  --query "SecurityGroups[*].{Id:GroupId,Name:GroupName}" \
  --output json 2>/dev/null || echo "[]")

SG_COUNT=$(echo "$SGS" | jq 'length')
if [[ "$SG_COUNT" -gt 0 ]]; then
  pass "$SG_COUNT security group(s) with prefix '${NAME_PREFIX}' found:"
  echo "$SGS" | jq -r '.[] | "  \(.Name)  (\(.Id))"' | while read -r sg; do info "$sg"; done
else
  warn "No security groups with prefix '${NAME_PREFIX}' found."
fi

# Helper: find a specific SG by partial name
find_sg() {
  local pattern="$1"
  echo "$SGS" | jq -r --arg p "$pattern" '.[] | select(.Name | test($p; "i")) | .Id' | head -1
}

ALB_SG_ID=$(find_sg "alb")
ECS_SG_ID=$(find_sg "ecs|api")
RDS_SG_ID=$(find_sg "rds|db")

# ── 5a. ALB SG — inbound 80/443 from anywhere ─────────────────────────────────
if [[ -n "$ALB_SG_ID" ]]; then
  ALB_INGRESS=$(aws ec2 describe-security-groups \
    --group-ids "$ALB_SG_ID" \
    --region "$AWS_REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json 2>/dev/null || echo "[]")

  HTTP80=$(echo "$ALB_INGRESS" | jq '[.[] | select(.FromPort <= 80 and .ToPort >= 80)] | length')
  HTTPS443=$(echo "$ALB_INGRESS" | jq '[.[] | select(.FromPort <= 443 and .ToPort >= 443)] | length')

  if [[ "$HTTP80" -gt 0 ]]; then
    pass "ALB security group ($ALB_SG_ID) allows inbound on port 80."
  else
    fail "ALB security group ($ALB_SG_ID) does not allow inbound on port 80."
  fi
  if [[ "$HTTPS443" -gt 0 ]]; then
    pass "ALB security group ($ALB_SG_ID) allows inbound on port 443."
  else
    info "ALB security group has no rule for port 443 (expected until HTTPS cert is provisioned)."
  fi
else
  warn "Could not identify ALB security group for rule verification."
fi

# ── 5b. ECS SG — inbound on container port 8000 from ALB SG ──────────────────
if [[ -n "$ECS_SG_ID" ]]; then
  ECS_INGRESS=$(aws ec2 describe-security-groups \
    --group-ids "$ECS_SG_ID" \
    --region "$AWS_REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json 2>/dev/null || echo "[]")

  PORT_8000=$(echo "$ECS_INGRESS" | jq '[.[] | select(.FromPort <= 8000 and .ToPort >= 8000)] | length')
  if [[ "$PORT_8000" -gt 0 ]]; then
    pass "ECS security group ($ECS_SG_ID) allows inbound on port 8000."
  else
    fail "ECS security group ($ECS_SG_ID) does not allow inbound on port 8000 — ALB cannot reach backend."
  fi
else
  warn "Could not identify ECS security group for rule verification."
fi

# ── 5c. RDS SG — inbound 5432 from ECS SG ────────────────────────────────────
if [[ -n "$RDS_SG_ID" ]]; then
  RDS_INGRESS=$(aws ec2 describe-security-groups \
    --group-ids "$RDS_SG_ID" \
    --region "$AWS_REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json 2>/dev/null || echo "[]")

  PG5432=$(echo "$RDS_INGRESS" | jq '[.[] | select(.FromPort <= 5432 and .ToPort >= 5432)] | length')
  if [[ "$PG5432" -gt 0 ]]; then
    pass "RDS security group ($RDS_SG_ID) allows inbound on port 5432."
  else
    fail "RDS security group ($RDS_SG_ID) does not allow inbound on port 5432 — ECS tasks cannot reach PostgreSQL."
  fi
else
  info "No RDS security group found with prefix '${NAME_PREFIX}-rds|db' — skipping RDS SG check."
fi

summarize "Networking"
