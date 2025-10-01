resource "aws_vpc" "myvpc"{
  cidr_block =  var.cidr
}

resource "aws_subnet" "sunbet1"{
    vpc_id = aws_vpc.myvpc.id
    cidr_block = "10.0.0.0/24" 
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
}
resource "aws_subnet" "sunbet2"{
    vpc_id = aws_vpc.myvpc.id
    cidr_block = "10.0.1.0/24" 
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
} 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}
resource "aws_route_table" "RT" {
    vpc_id = aws_vpc.myvpc.id
    route{
        cidr_block =  "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}
 resource "aws_route_table_association" "rta1" {
   subnet_id = aws_subnet.sunbet1.id
   route_table_id = aws_route_table.RT.id
 }

  resource "aws_route_table_association" "rta2" {
   subnet_id = aws_subnet.sunbet2.id
   route_table_id = aws_route_table.RT.id
 }

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.myvpc.id
  tags = {
    Name = "allow_tls"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4_2" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


resource "aws_s3_bucket" "example" {
  bucket = "my-tf-test-bucket-gloria"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}


# create IAM Role 
resource "aws_iam_role" "ec2_s3_role" {
  name = "ec2-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# create policy to access  S3
resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3-access-policy"
  description = "Policy for EC2 to access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.example.arn,
          "${aws_s3_bucket.example.arn}/*"
        ]
      }
    ]
  })
}

# attach policy to role
resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# create instance profile
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2-s3-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}


resource "aws_instance" "webserver1" {

    ami = "ami-0360c520857e3138f"
    instance_type ="t2.micro"
    vpc_security_group_ids = [aws_security_group.allow_tls.id]
    subnet_id = aws_subnet.sunbet1.id
    user_data = base64encode(file("userdata1.sh"))
    iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name
}


resource "aws_instance" "webserver2" {

    ami = "ami-0360c520857e3138f"
    instance_type ="t2.micro"
    vpc_security_group_ids = [aws_security_group.allow_tls.id]
    subnet_id = aws_subnet.sunbet2.id
    user_data = base64encode(file("userdata2.sh"))
    iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name
}


#create alb
resource "aws_lb" "myalb" {
  name = "myalb"
  internal = false
  load_balancer_type = "application"
  security_groups =  [aws_security_group.allow_tls.id]
  subnets =[aws_subnet.sunbet1.id,aws_subnet.sunbet2.id]

}

resource "aws_lb_target_group" "tg" {
  name = "myTG"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.myvpc.id
  health_check {
    path = "/"
    port = 80
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id = aws_instance.webserver1.id
  port = 80
}


resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id = aws_instance.webserver2.id
  port = 80
}

resource "aws_lb_listener" "listener" {
    load_balancer_arn = aws_lb.myalb.arn
    port = 80
    protocol = "HTTP"
    default_action {
        target_group_arn = aws_lb_target_group.tg.arn
        type = "forward"
    }
}

output "loadbalancerdns" {
    value = aws_lb.myalb.dns_name
}