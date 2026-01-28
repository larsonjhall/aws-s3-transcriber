output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "The URL of your web application"
}