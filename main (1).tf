provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# 1. S3 BUCKETS
resource "aws_s3_bucket" "source_bucket" {
  bucket = "podcast-audio-in-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "output_bucket" {
  bucket = "podcast-transcript-out-${random_id.suffix.hex}"
}

# 2. IAM ROLE
resource "aws_iam_role" "lambda_role" {
  name = "podcast_role_${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["transcribe:StartTranscriptionJob", "logs:*"]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*",
          aws_s3_bucket.output_bucket.arn,
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      }
    ]
  })
}

# 3. BUCKET POLICY
# 3a. SOURCE Bucket Policy (Allows Transcribe to Read)
resource "aws_s3_bucket_policy" "source_transcribe_access" {
  bucket = aws_s3_bucket.source_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTranscribeRead"
        Effect    = "Allow"
        Principal = { Service = "transcribe.amazonaws.com" }
        Action    = ["s3:GetObject", "s3:ListBucket"]
        # ONLY mention the source_bucket here
        Resource  = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
      }
    ]
  })
}

# 3b. OUTPUT Bucket Policy (Allows Transcribe to Write)
resource "aws_s3_bucket_policy" "output_transcribe_access" {
  bucket = aws_s3_bucket.output_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTranscribeWrite"
        Effect    = "Allow"
        Principal = { Service = "transcribe.amazonaws.com" }
        Action    = "s3:PutObject"
        # ONLY mention the output_bucket here
        Resource  = "${aws_s3_bucket.output_bucket.arn}/*"
      }
    ]
  })
}

# 4. LAMBDA FUNCTION
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "index.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "transcriber" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # The missing arguments Terraform was asking for:
  function_name    = "podcast_processor_${random_id.suffix.hex}"
  role             = aws_iam_role.lambda_role.arn
  
  # Essential settings:
  handler          = "index.lambda_handler"
  runtime          = "python3.12"

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}

# 5. S3 TRIGGER
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcriber.function_name # Check this matches your function resource name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

resource "aws_s3_bucket_notification" "trigger" {
  bucket = aws_s3_bucket.source_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.transcriber.arn
    events = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

# 6. AUTOMATED TEST AUDIO
resource "null_resource" "generate_audio" {
  provisioner "local-exec" {
    command = "aws polly synthesize-speech --output-format mp3 --voice-id Joanna --text 'Testing our San Diego podcast pipeline' test-podcast.mp3"
  }
}

resource "aws_s3_object" "upload_test" {
  depends_on = [null_resource.generate_audio]
  bucket     = aws_s3_bucket.source_bucket.id
  key        = "test-podcast.mp3"
  source     = "test-podcast.mp3"
}