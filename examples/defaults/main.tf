module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "default"

  cidr = "10.0.0.0/16"

  azs = [
  "${var.aws_region}a"]
  private_subnets = [
  "10.0.1.0/24"]
  public_subnets = [
  "10.0.101.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false
}

resource "aws_security_group" "this" {
  vpc_id = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = [
      22,
      80,
      443,
      5601,
      9200,
    9201]
    content {
      from_port = ingress.value
      to_port   = ingress.value
      protocol  = "tcp"
      cidr_blocks = [
      "0.0.0.0/0"]
    }
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }
}

module "defaults" {
  source    = "../.."
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [
  aws_security_group.this.id]
  public_key_path  = var.public_key_path
  private_key_path = var.private_key_path
}

variable "public_key_path" {}
variable "private_key_path" {}
