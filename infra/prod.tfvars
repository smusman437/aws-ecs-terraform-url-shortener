aws_region    = "us-east-1"
environment   = "prod"
desired_count = 2

enable_autoscaling = true
autoscaling_min    = 2
autoscaling_max    = 10
