# S3 Frontend Module — private bucket for React static assets
# CloudFront reads from this bucket via OAC (Origin Access Control).
# The bucket policy granting CloudFront access is managed in the cloudfront module
# to avoid a circular dependency (policy needs the distribution ARN).

resource "aws_s3_bucket" "this" {
  bucket = "${var.name_prefix}-frontend"
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
