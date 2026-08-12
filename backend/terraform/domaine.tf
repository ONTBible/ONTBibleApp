# Le domaine public — ontbible.com.
#
# Il sert trois choses, et c'est pour la première qu'il existe :
#
#   1. les **liens universels** : un lien partagé ouvre l'app si elle est
#      installée. Ça demande un fichier signé servi en clair à
#      /.well-known/apple-app-site-association, sans redirection ;
#   2. une **page de repli** pour qui n'a pas l'app, avec les balises Open
#      Graph qui donnent l'aperçu dans les messageries ;
#   3. une adresse stable, indépendante de l'identifiant execute-api que
#      change AWS si l'API est recréée.
#
# Le DNS reste chez Cloudflare : Terraform ne le gère pas, il produit les
# enregistrements à coller (voir les sorties en bas de ce fichier).

variable "domaine" {
  type        = string
  description = "Le domaine public. Vide = rien n'est créé, l'API reste sur son URL execute-api."
  default     = ""
}

locals {
  # Tout ce fichier est conditionnel : tant que `domaine` est vide, le plan
  # Terraform est identique à celui d'avant. Ça permet de committer le code
  # sans forcer personne à posséder le domaine.
  actif = var.domaine == "" ? 0 : 1
}

# ── Le certificat ────────────────────────────────────────────────────────────
#
# Dans la même région que l'API : un domaine personnalisé régional d'API
# Gateway refuse un certificat d'une autre région, y compris us-east-1, qui
# est pourtant l'usage pour CloudFront. C'est la confusion la plus courante.
resource "aws_acm_certificate" "domaine" {
  count             = local.actif
  domain_name       = var.domaine
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# On ne peut pas valider automatiquement : le DNS est chez Cloudflare. Cette
# ressource attend que les enregistrements soient posés à la main, et échoue
# après un délai plutôt que de bloquer indéfiniment.
resource "aws_acm_certificate_validation" "domaine" {
  count           = local.actif
  certificate_arn = aws_acm_certificate.domaine[0].arn

  timeouts {
    create = "20m"
  }
}

# ── Le domaine personnalisé ──────────────────────────────────────────────────

resource "aws_apigatewayv2_domain_name" "domaine" {
  count       = local.actif
  domain_name = var.domaine

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.domaine[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "domaine" {
  count       = local.actif
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_apigatewayv2_domain_name.domaine[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

# ── Ce qu'il reste à coller chez Cloudflare ──────────────────────────────────

output "dns_validation" {
  description = "L'enregistrement de validation du certificat, à créer chez Cloudflare (nuage gris)."
  value = local.actif == 0 ? [] : [
    for o in aws_acm_certificate.domaine[0].domain_validation_options : {
      type   = o.resource_record_type
      nom    = o.resource_record_name
      valeur = o.resource_record_value
    }
  ]
}

output "dns_domaine" {
  description = "L'enregistrement qui fait pointer le domaine vers l'API. Nuage GRIS obligatoire."
  value = local.actif == 0 ? null : {
    type   = "CNAME"
    nom    = var.domaine
    valeur = aws_apigatewayv2_domain_name.domaine[0].domain_name_configuration[0].target_domain_name
  }
}
