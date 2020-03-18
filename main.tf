provider "aws" {
  region = var.region
}


#############################################################################
##  Create the S3 Buckets and Policies here
#############################################################################
resource "aws_s3_bucket" "transcode" {
  bucket        = var.transcode-bucket-name
  region        = var.region
  force_destroy = true
}

resource "aws_s3_bucket_policy" "transcode_policy" {
  bucket = aws_s3_bucket.transcode.id

  policy     = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AddPerm",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${var.transcode-bucket-name}/*"]
    }
  ]
}
POLICY
  depends_on = [aws_s3_bucket_public_access_block.transcode_bucket_public_access_block]
}

resource "aws_s3_bucket_public_access_block" "transcode_bucket_public_access_block" {
  bucket             = aws_s3_bucket.transcode.id
  block_public_acls  = true
  ignore_public_acls = true
}

resource "aws_s3_bucket" "upload" {
  bucket        = var.upload-bucket-name
  region        = var.region
  force_destroy = true
  acl           = "private"
}

resource "aws_s3_bucket_public_access_block" "upload_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.upload.id
  block_public_policy     = true
  block_public_acls       = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
#############################################################################

#############################################################################
##  Create the IAM Roles and Policies Here
#############################################################################
resource "aws_iam_role" "et-role" {
  name               = "${var.ownername}-Elastic_Transcoder_Default_Role"
  assume_role_policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "elastictranscoder.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF  
}

resource "aws_iam_role_policy" "et-role-policy" {
  name = "${var.ownername}-et-policy"
  role = aws_iam_role.et-role.id

  policy = <<-EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Action": [
                "s3:Put*",
                "s3:ListBucket",
                "s3:*MultipartUpload*",
                "s3:Get*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "2",
            "Effect": "Allow",
            "Action": "sns:Publish",
            "Resource": "*"
        },
        {
            "Sid": "3",
            "Effect": "Deny",
            "Action": [
                "s3:*Delete*",
                "s3:*Policy*",
                "sns:*Remove*",
                "sns:*Delete*",
                "sns:*Permission*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "job-submitter" {
  name = var.job_submitter_name

  assume_role_policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "job-submitter-policy" {
  name = "${var.job_submitter_name}-policy"
  role = aws_iam_role.job-submitter.id

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "elastictranscoder:Read*",
        "elastictranscoder:List*",
        "elastictranscoder:*Job",
        "elastictranscoder:*Preset",
        "s3:ListAllMyBuckets",
        "s3:ListBucket",
        "iam:ListRoles",
        "sns:ListTopics"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
EOF
}
#############################################################################

#############################################################################
##  Create the Elastic Transcoder Here
#############################################################################
resource "aws_elastictranscoder_pipeline" "video" {
  input_bucket = aws_s3_bucket.upload.bucket
  name         = "aws_elastictranscoder_pipeline_${var.ownername}"
  role         = aws_iam_role.et-role.arn

  content_config {
    bucket        = aws_s3_bucket.transcode.bucket
    storage_class = "Standard"
  }

  thumbnail_config {
    bucket        = aws_s3_bucket.transcode.bucket
    storage_class = "Standard"
  }
}
#############################################################################

#############################################################################
##  Create the Lambda Transcode Function Here
#############################################################################
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcode_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload.arn
}

resource "aws_lambda_function" "transcode_lambda" {
  filename      = "Lambda-Deployment.zip"
  function_name = "${var.ownername}-transcoder_function"
  role          = aws_iam_role.job-submitter.arn
  handler       = "index.handler"
  timeout       = 30

  source_code_hash = filebase64sha256("Lambda-Deployment.zip")

  runtime = "nodejs10.x"
  environment {
    variables = {
      ELASTIC_TRANSCODER_PIPELINE_ID = aws_elastictranscoder_pipeline.video.id
      ELASTIC_TRANSCODER_REGION      = var.region
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.upload.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcode_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    #filter_prefix       = "AWSLogs/"
    #filter_suffix       = ".log"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
#############################################################################