resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "public_sg" {
  name        = "allow_ssh"
  description = "Allow SSH connection from the specific Public IP"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "public-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.public_sg.id
  cidr_ipv4         = var.principal_public_ip
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "default_egress_rule" {
  security_group_id = aws_security_group.public_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "vpce_sg" {
  name        = "secrets_manager_vpce_sg"
  description = "Allow TLS inbound from the VPC to the Secrets Manager Endpoint"
  vpc_id      = aws_vpc.main_vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls" {
  security_group_id = aws_security_group.vpce_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = aws_vpc.main_vpc.cidr_block
}

resource "aws_vpc_endpoint" "sm_vpc_endpoint" {
  vpc_id       = aws_vpc.main_vpc.id
  service_name = "com.amazonaws.${var.aws_region}.secretsmanager"

  vpc_endpoint_type = "Interface"

  subnet_ids          = [aws_subnet.public_subnet.id]
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true
}

resource "aws_kms_key" "app_key" {
  description             = "The key for encrypting app secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_secretsmanager_secret" "app_secret" {
  name_prefix = "${var.secret_name}-"
  description = "Application database credentials"
  kms_key_id  = aws_kms_key.app_key.arn
}

resource "aws_secretsmanager_secret_version" "app_secret_value" {
  secret_id = aws_secretsmanager_secret.app_secret.id

  secret_string = jsonencode({
    username = "${var.user_name}"
    password = "${var.user_password}"
  })
}

data "aws_iam_policy_document" "ec2_assume_policy" {
  statement {
    sid     = "AllowEC2ToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_secrets_role" {
  name               = "ec2_secrets_access_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_policy.json
}

data "aws_iam_policy_document" "secrets_permission_doc" {
  statement {
    sid    = "AllowSecretsManagerRead"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [aws_secretsmanager_secret.app_secret.arn]
  }

  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"

    actions = [
      "kms:Decrypt"
    ]

    resources = [aws_kms_key.app_key.arn]
  }
}

resource "aws_iam_policy" "secrets_policy" {
  name        = "secret_permission_policy"
  description = "Allow reading secrets from SM and decrypting them via KMS"
  policy      = data.aws_iam_policy_document.secrets_permission_doc.json
}

resource "aws_iam_role_policy_attachment" "attach_secret_policy" {
  role       = aws_iam_role.ec2_secrets_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_secrets_role.name
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }
}

resource "aws_key_pair" "def_key" {
  key_name   = "def_key"
  public_key = file("~/.ssh/def-key.pub")
}

resource "aws_instance" "public_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  key_name               = aws_key_pair.def_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = file("${path.module}/scripts/userdata.sh")
}