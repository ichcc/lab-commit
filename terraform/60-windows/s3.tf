resource "aws_s3_bucket" "installers" {
  bucket        = "${var.project}-installers-${local.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "installers" {
  bucket                  = aws_s3_bucket.installers.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "installers" {
  bucket = aws_s3_bucket.installers.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "installers" {
  bucket = aws_s3_bucket.installers.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
