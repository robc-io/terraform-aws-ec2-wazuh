resource "random_pet" "this" {}

module "label" {
  source = "github.com/robc-io/terraform-null-label.git?ref=0.16.1"
  tags = {
    NetworkName = var.network_name
    Owner       = var.owner
    Terraform   = true
    VpcType     = "main"
  }

  environment = var.environment
  namespace   = var.namespace
  stage       = var.stage
}

module "ami" {
  source = "github.com/insight-infrastructure/terraform-aws-ami.git?ref=master"
}

resource "aws_eip" "this" {
  tags       = merge({ Name = "wazuh-server" }, module.label.tags)
  depends_on = [aws_instance.this]
}

resource "aws_eip_association" "this" {
  instance_id = aws_instance.this.id
  public_ip   = aws_eip.this.public_ip
}

resource "aws_key_pair" "this" {
  count      = var.public_key_path == "" ? 0 : 1
  public_key = file(var.public_key_path)
}

resource "aws_iam_role" "this" {
  name               = "${module.label.name}Role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = module.label.tags
}

resource "aws_iam_instance_profile" "this" {
  name = "${module.label.name}InstanceProfile"
  role = aws_iam_role.this.name
}

resource "aws_iam_policy" "json_policy" {
  name   = "${module.label.name}Policy"
  policy = <<-EOT
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"ReadWrite",
      "Effect":"Allow",
      "Action":["s3:GetObject", "s3:PutObject"],
      "Resource":["arn:aws:s3:::${aws_s3_bucket.this.bucket}/*"]
    }
  ]
}
EOT
}

resource "aws_iam_role_policy_attachment" "json_policy" {
  role = aws_iam_role.this.id

  policy_arn = aws_iam_policy.json_policy.arn
}

resource "aws_instance" "this" {
  ami           = module.ami.ubuntu_1804_ami_id
  instance_type = var.instance_type

  root_block_device {
    volume_size = var.root_volume_size
  }

  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids

  key_name             = var.public_key_path == "" ? var.key_name : aws_key_pair.this.*.key_name[0]
  iam_instance_profile = aws_iam_instance_profile.this.id

  tags = module.label.tags
}

data "aws_caller_identity" "this" {}

resource "aws_s3_bucket" "this" {
  bucket = "wazuh-logs-${data.aws_caller_identity.this.account_id}"
  acl    = "private"

  tags = module.label.tags
}

module "ansible" {
  source = "github.com/insight-infrastructure/terraform-aws-ansible-playbook.git?ref=master"
  ip     = aws_eip_association.this.public_ip

  user             = "ubuntu"
  private_key_path = var.private_key_path

  playbook_file_path = "${path.module}/ansible/main.yml"
  playbook_vars      = {}

  requirements_file_path = "${path.module}/ansible/requirements.yml"
}
