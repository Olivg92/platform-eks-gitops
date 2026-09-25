variable "name" {
  description = "Cluster name, also used as a prefix for its roles."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Keep it on standard support: extended support costs $0.50/hour extra."
  type        = string
  default     = "1.36"
}

variable "subnet_ids" {
  description = "Subnets the control plane and the nodes live in."
  type        = list(string)
}

variable "instance_types" {
  description = "Instance types the Spot node group may pick from."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "desired_size" {
  description = "Number of nodes."
  type        = number
  default     = 2
}

variable "disk_size_gb" {
  description = "Root volume of each node, in GB."
  type        = number
  default     = 20
}

variable "public_access_cidrs" {
  description = "Who may reach the Kubernetes API. Required: there is no sensible default."
  type        = list(string)
}
