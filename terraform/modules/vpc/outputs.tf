output "vpc_id" {
  description = "Id of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Ids of the public subnets, one per availability zone."
  value       = [for subnet in aws_subnet.public : subnet.id]
}
