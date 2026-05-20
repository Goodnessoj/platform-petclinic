variable "environment" {
  description = "Environment name used for bootstrap resource tags."
  type        = string
  default     = "bootstrap"
}

variable "project_name" {
  description = "Project identifier used for naming."
  type        = string
  default     = "petclinic"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-2"
}

variable "repository_prefix" {
  description = "Plain ECR repository prefix that GitHub Actions can push to."
  type        = string
  default     = "petclinic-dev"
}

variable "github_repositories" {
  description = "GitHub repositories allowed to assume the deployment role."
  type = list(object({
    owner        = string
    name         = string
    branches     = optional(list(string), ["main"])
    environments = optional(list(string), [])
  }))
  default = [
    {
      owner        = "Goodnessoj"
      name         = "platform-petclinic"
      branches     = ["main"]
      environments = ["dev", "prod"]
    },
    {
      owner        = "official-mary"
      name         = "spring-petclinic-microservices"
      branches     = ["main"]
      environments = []
    }
  ]
}

variable "github_actions_role_name" {
  description = "IAM role name assumed by GitHub Actions."
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "terraform_state_bucket_name" {
  description = "S3 bucket name used by Terraform backends."
  type        = string
  default     = "petclinic-tfstate-974263620909"
}

variable "platform_state_key_prefix" {
  description = "S3 key prefix containing the disposable platform Terraform state."
  type        = string
  default     = "petclinic/dev"
}

variable "prod_state_key_prefix" {
  description = "S3 key prefix containing the production platform Terraform state."
  type        = string
  default     = "petclinic/prod"
}

variable "bootstrap_state_key_prefix" {
  description = "S3 key prefix containing this bootstrap root's Terraform state."
  type        = string
  default     = "petclinic/bootstrap"
}

variable "terraform_state_kms_key_arn" {
  description = "Optional KMS key ARN used by the Terraform backend bucket."
  type        = string
  default     = ""
}

variable "state_bucket_guardrail_exempt_principal_arns" {
  description = "Additional break-glass principal ARNs allowed to delete the Terraform state bucket or state object versions."
  type        = list(string)
  default     = []
}
