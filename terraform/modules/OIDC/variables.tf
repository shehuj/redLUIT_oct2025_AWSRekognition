variable "6938fd4d98bab03faadb97b34396831e3780aea1" {
  description = "The thumbprint for GitHub Actions OIDC provider"
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1" 
  
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "The GitHub repository in the format 'Owner/Repo'"
  type        = string
  default     = "shehuj/redLUIT_oct2025_AWSRekognition"
}

variable "github_branch" {
  description = "The GitHub branch to allow OIDC access from"
  type        = string
  default     = "dev"
}

variable "role_name" {
  description = "The name of the IAM role to be created for GitHub Actions"
  type        = string
  default     = "GitHubActionsOIDCRole"
}