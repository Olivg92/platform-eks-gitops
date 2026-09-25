variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "cidr_block" {
  description = "CIDR of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread the public subnets across."
  type        = list(string)
}
