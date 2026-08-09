output "aws_public_ip" {
    description = "The Public Ip of the EC2 instance"
    value = aws_instance.public_instance.public_ip
}