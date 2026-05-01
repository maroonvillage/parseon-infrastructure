# resource "aws_kms_key" "this" {
#   description             = "KMS key for ${var.name_prefix}"
#   deletion_window_in_days = var.deletion_window_in_days
#   enable_key_rotation     = true

#   tags = {
#     Name = "${var.name_prefix}-kms"
#   }
# }

# resource "aws_kms_alias" "this" {
#   name          = "alias/${var.name_prefix}"
#   target_key_id = aws_kms_key.this.key_id
# }
