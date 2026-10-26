# Optional certificate in an existing hosted zone. The API alias record is
# deliberately deferred until Task 4 creates the controller-managed ALB.
resource "aws_acm_certificate" "api" {
  count             = var.domain_name == null ? 0 : 1
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = var.hosted_zone_id != null
      error_message = "A domain_name requires an existing hosted_zone_id."
    }
  }
}
resource "aws_route53_record" "certificate_validation" {
  count   = var.domain_name == null ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = one(aws_acm_certificate.api[0].domain_validation_options).resource_record_name
  type    = one(aws_acm_certificate.api[0].domain_validation_options).resource_record_type
  ttl     = 60
  records = [one(aws_acm_certificate.api[0].domain_validation_options).resource_record_value]
}
resource "aws_acm_certificate_validation" "api" {
  count                   = var.domain_name == null ? 0 : 1
  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [aws_route53_record.certificate_validation[0].fqdn]
}
