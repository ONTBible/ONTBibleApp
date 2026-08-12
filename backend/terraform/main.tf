terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Paris, et non la Virginie. Les surlignages d'un lecteur de Bible révèlent des
# convictions religieuses — catégorie particulière au sens de l'article 9 du
# RGPD. Héberger dans l'Union n'est pas obligatoire en soi, mais c'est ce qui
# rend la conformité simple à établir et à démontrer.
# Identité dédiée à l'ONT — surtout pas celle de Pinkha : si une clé fuite,
# elle ne doit donner accès qu'à ce projet. Ses droits sont bornés aux
# ressources « ont-* » de cette région (politique IAM « ont-deploy »).
provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = {
      Project = "la-bible-ont"
      Managed = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-3"
}

variable "profile" {
  type    = string
  default = "ont"
}

variable "jwt_secret" {
  type      = string
  sensitive = true
  # Aucune valeur par défaut : passée par TF_VAR_jwt_secret, jamais écrite
  # dans le dépôt. Générer avec : openssl rand -base64 48
}

variable "apple_client_id" {
  type    = string
  default = ""
}
variable "apple_team_id" {
  type    = string
  default = ""
}
variable "apple_key_id" {
  type    = string
  default = ""
}
variable "apple_private_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "google_client_id" {
  type    = string
  default = ""
}
variable "google_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "github_client_id" {
  type    = string
  default = ""
}
variable "github_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# Le DSN Sentry n'est pas un secret : il n'autorise qu'à *écrire* des
# événements, jamais à en lire. Il reste une variable pour ne pas figer un
# projet dans le code.
variable "sentry_dsn" {
  type    = string
  default = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Stockage
# ─────────────────────────────────────────────────────────────────────────────

# Table unique : toutes nos lectures partent d'un lecteur connu, donc une clé
# de partition par lecteur et un tri par préfixe suffisent.
#
# Facturation à la demande plutôt que provisionnée : le trafic d'une liseuse
# est erratique (des pics le dimanche matin, rien la nuit) et le volume reste
# minuscule. Provisionner de la capacité coûterait plus cher et demanderait
# une surveillance dont on n'a pas besoin.
resource "aws_dynamodb_table" "ont" {
  name         = "ont"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "digest"
    type = "S"
  }

  # Retrouver un jeton de rafraîchissement par son empreinte, sans connaître
  # le lecteur — c'est justement ce que le client ne nous dit pas encore au
  # moment où il présente son jeton.
  global_secondary_index {
    name               = "by-digest"
    hash_key           = "digest"
    projection_type    = "INCLUDE"
    non_key_attributes = ["user"]
  }

  # Les jetons de rafraîchissement expirent d'eux-mêmes : pas de tâche de
  # ménage à écrire, ni à surveiller.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Calcul
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "ont-api"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Droits au strict nécessaire, et sur la seule table concernée — pas de
# `dynamodb:*` sur `*`.
data "aws_iam_policy_document" "lambda" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.ont.arn,
      "${aws_dynamodb_table.ont.arn}/index/*",
    ]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# Rétention explicite : sans elle, CloudWatch garde les traces indéfiniment et
# la facture de logs finit par dépasser celle du calcul.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/ont-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "api" {
  function_name = "ont-api"
  role          = aws_iam_role.lambda.arn

  # `provided.al2023` + binaire Rust : démarrage à froid de quelques
  # millisecondes, là où un runtime managé en prend 150 à 300.
  runtime       = "provided.al2023"
  handler       = "bootstrap"
  architectures = ["arm64"]

  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)

  memory_size = 256
  timeout     = 15

  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.ont.name
      SENTRY_DSN           = var.sentry_dsn
      JWT_SECRET           = var.jwt_secret
      APPLE_CLIENT_ID      = var.apple_client_id
      APPLE_TEAM_ID        = var.apple_team_id
      APPLE_KEY_ID         = var.apple_key_id
      APPLE_PRIVATE_KEY    = var.apple_private_key
      GOOGLE_CLIENT_ID     = var.google_client_id
      GOOGLE_CLIENT_SECRET = var.google_client_secret
      GITHUB_CLIENT_ID     = var.github_client_id
      GITHUB_CLIENT_SECRET = var.github_client_secret
      RUST_LOG             = "info,ont_backend=info"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

variable "package_path" {
  type    = string
  default = "../target/lambda/ont-backend/bootstrap.zip"
}

# ─────────────────────────────────────────────────────────────────────────────
# Façade
# ─────────────────────────────────────────────────────────────────────────────

# HTTP API et non REST API : même service, 1 $ le million de requêtes contre
# 3,50 $. Le REST API n'apporte ici que des fonctions qu'on n'utilise pas.
resource "aws_apigatewayv2_api" "api" {
  name          = "ont-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "PUT", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "any" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Une limite de débit dès le premier jour : sans elle, une boucle dans une
  # version de l'app peut transformer une facture de 3 $ en facture à trois
  # chiffres pendant la nuit.
  default_route_settings {
    throttling_burst_limit = 200
    throttling_rate_limit  = 100
  }
}

resource "aws_lambda_permission" "api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_url" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "À reporter dans Secrets.xcconfig côté app iOS."
}
