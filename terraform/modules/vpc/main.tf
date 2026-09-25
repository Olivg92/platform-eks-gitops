# A deliberately small VPC: public subnets only, no NAT Gateway.
#
# The usual production layout puts nodes in private subnets behind a NAT Gateway,
# which costs $0.045/hour plus $0.045 per GB processed, per availability zone.
# For a cluster that lives for a few hours that is the single most expensive
# resource, and it protects against inbound traffic that security groups already
# refuse. See docs/adr/0009 for the full reasoning and what production would do.

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "public" {
  for_each = { for index, az in var.availability_zones : az => index }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.cidr_block, 4, each.value)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${each.key}"
    # Tells the in-cluster load balancer controller it may create public load
    # balancers in this subnet.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# The default security group of a VPC allows all traffic between its members.
# Emptying it means anything that ends up using it by accident is isolated.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-default-do-not-use"
  }
}
