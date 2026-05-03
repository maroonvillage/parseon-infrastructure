output "app_bucket_name" {
  value = module.s3.bucket_name
}

output "app_bucket_arn" {
  value = module.s3.bucket_arn
}

output "frontend_bucket_name" {
  value = module.s3_frontend.bucket_name
}

output "frontend_bucket_arn" {
  value = module.s3_frontend.bucket_arn
}
