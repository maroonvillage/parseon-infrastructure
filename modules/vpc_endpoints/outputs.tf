output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}


