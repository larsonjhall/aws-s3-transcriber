resource "aws_ecr_repository" "app" {
  name         = "my-app-repo" # Must match exactly what you typed in the CLI
  force_delete = true
}