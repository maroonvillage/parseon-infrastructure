output "queue_url" {
  value = aws_sqs_queue.this.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}
