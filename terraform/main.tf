provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for Static Website
resource "aws_s3_bucket" "static_site" {
  bucket = "my-static-website-ayush"
  acl    = "public-read"

  website {
    index_document = "index.html"
  }
}

# S3 Bucket Policy to Allow Public Access
resource "aws_s3_bucket_policy" "public_access" {
  bucket = aws_s3_bucket.static_site.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-static-website-ayush/*"
    }
  ]
}
POLICY
}

# Upload index.html to S3
resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.static_site.id
  key    = "index.html"
  source = "./index.html"
  content_type = "text/html"
}

# CloudFront Distribution for CDN
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# AWS WAF Web ACL
resource "aws_wafv2_web_acl" "web_acl" {
  name        = "static-site-waf"
  scope       = "CLOUDFRONT"
  description = "Web ACL for static website"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      sampled_requests_enabled = true
      cloudwatch_metrics_enabled = true
      metric_name = "waf-metric"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name = "waf-visibility"
    sampled_requests_enabled = true
  }
}

# Route 53 DNS Record (Assuming domain is registered in Route 53)
resource "aws_route53_record" "static_site" {
  zone_id = "YOUR_ROUTE_53_ZONE_ID"
  name    = "my-static-website-ayush.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudWatch Metric to Monitor S3 Access Logs
resource "aws_cloudwatch_metric_alarm" "s3_requests" {
  alarm_name          = "S3AccessAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "NumberOfObjects"
  namespace          = "AWS/S3"
  period             = "300"
  statistic          = "Sum"
  threshold          = "1000"
  alarm_description  = "Alarm when S3 object requests exceed 1000 in 5 minutes"

  dimensions = {
    BucketName = aws_s3_bucket.static_site.id
    StorageType = "StandardStorage"
  }

  actions_enabled = false
}
