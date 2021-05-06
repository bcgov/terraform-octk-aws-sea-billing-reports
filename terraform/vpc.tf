# resource "aws_vpc" "private_vpc" {
#   cidr_block = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   enable_dns_support = true
#   tags = merge(map( 
#             "Name", "private_vpc"
#         ), 
#         local.common_tags)
# }


# resource "aws_subnet" "private_vpc_subnet_a" {
#   vpc_id     = aws_vpc.private_vpc.id
#   cidr_block = "10.0.1.0/24"
#   availability_zone = "ca-central-1a"
#    tags = merge(map( 
#             "Name", "private_vpc_subnet_a"
#         ), 
#         local.common_tags)
# }

# resource "aws_subnet" "private_vpc_subnet_b"  {
#   vpc_id     = aws_vpc.private_vpc.id
#   cidr_block = "10.0.2.0/24"
#   availability_zone = "ca-central-1b"
#   tags = merge(map( 
#             "Name", "private_vpc_subnet_b"
#         ), 
#         local.common_tags)
# }

# resource "aws_vpc_endpoint" "efs" {
#   vpc_id            = aws_vpc.private_vpc.id
#   service_name      = "com.amazonaws.ca-central-1.elasticfilesystem"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.allow_efs.id,
#   ]

#   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

#   private_dns_enabled = true
# }



# resource "aws_security_group" "allow_efs" {
#   name        = "allow_efs"
#   description = "Allow EFS inbound traffic"
#   vpc_id      = aws_vpc.private_vpc.id

#   ingress {
#     description = "EFS Port"
#     from_port   = 2049
#     to_port     = 2049
#     protocol    = "tcp"
#     cidr_blocks = [aws_vpc.private_vpc.cidr_block]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#    tags = merge(map( 
#             "Name", "allow_efs_sg"
#         ), 
#         local.common_tags)
# }

# # resource "aws_internet_gateway" "gw" {
# #   vpc_id = aws_vpc.private_vpc.id

# #   tags = local.common_tags
# # }


# resource "aws_security_group" "endpoint_sg" {
#   name        = "endpoint_sg"
#   description = "Allow TLS inbound traffic"
#   vpc_id      = aws_vpc.private_vpc.id

#   ingress {
#     description = "TLS Port"
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = [aws_vpc.private_vpc.cidr_block]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#    tags = merge(map( 
#              "Name", "endpoint_sg"
#          ), 
#          local.common_tags)
#  }



# # resource "aws_vpc_endpoint" "ssm" {
# #   vpc_id            = aws_vpc.private_vpc.id
# #   service_name      = "com.amazonaws.ca-central-1.ssm"
# #   vpc_endpoint_type = "Interface"

# #   security_group_ids = [
# #     aws_security_group.endpoint_sg.id,
# #   ]

# #   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

# #   private_dns_enabled = true

# #    tags = local.common_tags
# # }


# # resource "aws_vpc_endpoint" "ssmmessages" {
# #   vpc_id            = aws_vpc.private_vpc.id
# #   service_name      = "com.amazonaws.ca-central-1.ssmmessages"
# #   vpc_endpoint_type = "Interface"

# #   security_group_ids = [
# #     aws_security_group.endpoint_sg.id,
# #   ]

# #   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

# #   private_dns_enabled = true

# #    tags = local.common_tags
# # }


# # resource "aws_vpc_endpoint" "ec2-messages" {
# #   vpc_id            = aws_vpc.private_vpc.id
# #   service_name      = "com.amazonaws.ca-central-1.ec2messages"
# #   vpc_endpoint_type = "Interface"

# #   security_group_ids = [
# #     aws_security_group.endpoint_sg.id,
# #   ]

# #   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

# #   private_dns_enabled = true

# #    tags = local.common_tags
# # }



# resource "aws_vpc_endpoint" "kms" {
#   vpc_id            = aws_vpc.private_vpc.id
#   service_name      = "com.amazonaws.ca-central-1.kms"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.endpoint_sg.id,
#   ]

#   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

#   private_dns_enabled = true

#    tags = local.common_tags
# }



# resource "aws_vpc_endpoint" "logs" {
#   vpc_id            = aws_vpc.private_vpc.id
#   service_name      = "com.amazonaws.ca-central-1.logs"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.endpoint_sg.id,
#   ]

#   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

#   private_dns_enabled = true

#    tags = local.common_tags
# }


# resource "aws_vpc_endpoint" "athena" {
#   vpc_id            = aws_vpc.private_vpc.id
#   service_name      = "com.amazonaws.ca-central-1.athena"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.endpoint_sg.id,
#   ]

#   subnet_ids = [ aws_subnet.private_vpc_subnet_a.id,  aws_subnet.private_vpc_subnet_b.id]

#   private_dns_enabled = true

#    tags = local.common_tags
# }



# resource "aws_vpc_endpoint" "s3" {
#   vpc_id       = aws_vpc.private_vpc.id
#   service_name = "com.amazonaws.ca-central-1.s3"

#   route_table_ids = [ aws_vpc.private_vpc.default_route_table_id ]

#    tags = local.common_tags
# }