output "aws_region" {
  value = var.aws_region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_arn" {
  value = module.alb.alb_arn
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

output "frontend_bucket_id" {
  value = module.s3_frontend.bucket_id
}

output "frontend_bucket_arn" {
  value = module.s3_frontend.bucket_arn
}

output "frontend_bucket_regional_domain_name" {
  value = module.s3_frontend.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "cloudfront_distribution_arn" {
  value = module.cloudfront.distribution_arn
}

output "cloudfront_domain_name" {
  value = module.cloudfront.cloudfront_domain_name
}

output "index_object_key" {
  value = aws_s3_object.index.key
}

output "api_path_pattern" {
  value = "/api/*"
}
