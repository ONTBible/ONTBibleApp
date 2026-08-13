# `api.ontbible.com` — l'adresse propre de l'API.
#
# ## Pourquoi elle existe
#
# `ontbible.com` sert aujourd'hui deux choses de nature opposée : l'API de
# l'app, et les pages publiques (les liens universels, la page de repli d'un
# passage). Le site les reprend, et il les rend mieux — il a le corpus.
#
# L'API a donc besoin de son propre nom. Pas pour l'app d'aujourd'hui, qui
# appelle directement son adresse `execute-api` : pour que le jour où elle
# passera par un nom de domaine, ce nom ne soit pas celui du site.
#
# ## Elle est **additive**
#
# Ce fichier ne touche à rien d'existant. `ontbible.com` continue de répondre
# exactement comme avant, avec son certificat et son mappage. Les deux noms
# servent la même API en parallèle, aussi longtemps qu'on veut — c'est ce
# recouvrement qui rend la bascule réversible.
#
# ## Le certificat est régional, et c'est l'inverse du site
#
# Un domaine personnalisé **régional** d'API Gateway refuse un certificat d'une
# autre région, y compris `us-east-1`. CloudFront, lui, n'accepte **que**
# `us-east-1`. Les deux règles sont opposées, et chacune est absolue : c'est la
# confusion la plus courante quand on monte les deux le même jour.

variable "api_domaine" {
  type        = string
  description = "L'adresse propre de l'API. Vide = rien n'est créé."
  default     = ""
}

locals {
  api_actif = var.api_domaine == "" ? 0 : 1
}

resource "aws_acm_certificate" "api" {
  count             = local.api_actif
  domain_name       = var.api_domaine
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "api" {
  count           = local.api_actif
  certificate_arn = aws_acm_certificate.api[0].arn

  timeouts {
    create = "20m"
  }
}

resource "aws_apigatewayv2_domain_name" "api" {
  count       = local.api_actif
  domain_name = var.api_domaine

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  count       = local.api_actif
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_apigatewayv2_domain_name.api[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

# ── Ce qu'il reste à coller chez Cloudflare ──────────────────────────────────

output "api_dns_validation" {
  description = "La validation du certificat de api.ontbible.com. Nuage GRIS."
  value = local.api_actif == 0 ? [] : [
    for o in aws_acm_certificate.api[0].domain_validation_options : {
      type   = o.resource_record_type
      nom    = o.resource_record_name
      valeur = o.resource_record_value
    }
  ]
}

output "api_dns_domaine" {
  description = "L'enregistrement qui fait pointer api.ontbible.com vers l'API. Nuage GRIS obligatoire."
  value = local.api_actif == 0 ? null : {
    type   = "CNAME"
    nom    = var.api_domaine
    # Le proxy orange de Cloudflare casse le TLS d'un domaine personnalisé
    # d'API Gateway : il présente son propre certificat, et le nom ne
    # correspond plus. Nuage gris, sans exception.
    valeur = aws_apigatewayv2_domain_name.api[0].domain_name_configuration[0].target_domain_name
  }
}
