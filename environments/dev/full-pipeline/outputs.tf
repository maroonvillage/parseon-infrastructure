# output "alb_dns" {
#   value = module.api.alb_dns
# }

# output "bucket_name" {
#   value = module.s3.bucket_name
# }

# output "queue_url" {
#   value = module.sqs.queue_url
# }
output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "queue_url" {
  value = aws_sqs_queue.q.id
}
