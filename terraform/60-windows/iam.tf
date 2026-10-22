data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "windows" {
  name               = "${var.project}-windows"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.windows.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "setup" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.installers.arn}/*"]
  }

  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.ca_parameter}",
      aws_ssm_parameter.admin_password.arn,
    ]
  }
}

resource "aws_iam_role_policy" "setup" {
  name   = "windows-setup"
  role   = aws_iam_role.windows.id
  policy = data.aws_iam_policy_document.setup.json
}

resource "aws_iam_instance_profile" "windows" {
  name = "${var.project}-windows"
  role = aws_iam_role.windows.name
}
