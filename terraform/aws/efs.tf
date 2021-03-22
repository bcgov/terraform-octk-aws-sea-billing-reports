# resource "aws_efs_file_system" "process-cur" {
#   creation_token = "process-cur"
#   kms_key_id  = var.kms_master_key_id
#   encrypted = true
#   tags = merge(map( 
#           "Name", "process-cur"
#       ), 
#       local.common_tags)
# }

# resource "aws_efs_mount_target" "alpha" {
#   file_system_id = aws_efs_file_system.process-cur.id
#   subnet_id      = aws_subnet.private_vpc_subnet_a.id
#   security_groups = [ aws_security_group.allow_efs.id ]
# }

# resource "aws_efs_mount_target" "beta" {
#   file_system_id = aws_efs_file_system.process-cur.id
#   subnet_id      = aws_subnet.private_vpc_subnet_b.id
#   security_groups = [ aws_security_group.allow_efs.id ]
# }


# resource "aws_efs_access_point" "access_point_for_lambda" {
#   file_system_id = aws_efs_file_system.process-cur.id

#   root_directory {
#     path = "/lambda"
#     creation_info {
#       owner_gid   = 1000
#       owner_uid   = 1000
#       permissions = "777"
#     }
#   }

#   posix_user {
#     gid = 1000
#     uid = 1000
#   }

#   tags = merge(map( 
#           "Name", "lambda"
#       ), 
#       local.common_tags)
# }