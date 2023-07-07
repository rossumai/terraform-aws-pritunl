data "aws_ami" "oracle" {
  most_recent = true

  filter {
    name   = "name"
    values = ["OL8.7-x86_64-HVM-2023-03-07"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["131827586825"] # Oracle
}

resource "aws_instance" "pritunl" {
  ami                  = data.aws_ami.oracle.id
  instance_type        = var.instance_type
  key_name             = var.aws_key_name
  user_data            = file("${path.module}/provision.sh")
  iam_instance_profile = var.iam_instance_profile
  root_block_device {
    volume_size           = var.volume_size
    tags                  = merge(tomap({ "Name" = format("%s-%s", var.resource_name_prefix, "vpn") }), var.tags, )
    delete_on_termination = false # we want' to keep our old HD for VPN - better to remove it manually later
    volume_type           = "gp3"
  }

  # When user-data changes I want to preserve instance as I can make changes on the machine or I can taint the resource if needed.
  lifecycle {
    ignore_changes = [user_data]
  }

  vpc_security_group_ids = compact([
    aws_security_group.pritunl.id,
    var.additional_security_group
  ])

  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  tags                        = merge(tomap({ "Name" = format("%s-%s", var.resource_name_prefix, "vpn") }), var.tags, )
}

resource "aws_eip" "pritunl" {
  instance = aws_instance.pritunl.id
  vpc      = true
  tags     = merge(tomap({ "Name" = format("%s-%s", var.resource_name_prefix, "vpn") }), var.tags, )
}
