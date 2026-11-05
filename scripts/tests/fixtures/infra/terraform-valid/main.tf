# Minimal static fixture — no remote backend, no provider credentials.
terraform {
  required_version = ">= 1.0"
}

locals {
  greeting = "hello"
}

output "greeting" {
  value = local.greeting
}
