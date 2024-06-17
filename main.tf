provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "backup_bucket" {
  bucket = "my-backup-bucket-unique-name-123456"
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_bucket_lifecycle" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    id     = "log"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_instance" "app" {
  ami           = "ami-08a0d1e16fc3f61ea"
  instance_type = "t2.micro"

  tags = {
    Name = "AppInstance"
  }
}

resource "aws_elb" "main" {
  name               = "my-elb"
  availability_zones = ["us-east-1a", "us-east-1b"]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.app.id]

  tags = {
    Name = "my-elb"
  }
}

resource "aws_route53_zone" "primary" {
  name = "tosinexample.mydomain.com"
}

resource "aws_route53_record" "failover" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "failover.tosinexample.mydomain.com"
  type    = "A"
  set_identifier = "primary"

  alias {
    name                   = aws_elb.main.dns_name
    zone_id                = aws_elb.main.zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_db_instance" "primary" {
  identifier              = "primary-instance"
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "root"
  password                = "password"
  engine_version          = "5.7"
  parameter_group_name    = "default.mysql5.7"
  skip_final_snapshot     = true
  multi_az                = true
  publicly_accessible     = false
  backup_retention_period = 7
}

variable "primary_db_arn" {
  default = "arn:aws:rds:us-east-1:147360193006:db:primary-instance"
}

resource "aws_db_instance" "replica" {
  identifier              = "replica-instance"
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  parameter_group_name    = "default.mysql5.7"
  skip_final_snapshot     = true
  multi_az                = true
  publicly_accessible     = false
  replicate_source_db     = var.primary_db_arn

  depends_on = [aws_db_instance.primary]
}
