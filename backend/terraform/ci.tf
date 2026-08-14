// Le rôle que GitHub emprunte pour remplacer le code du backend.
//
// Même montage que celui du site (`ONTBibleWebapp/infra/ci.tf`), et
// délibérément la même forme : deux rôles qui font la même chose de deux
// façons différentes finissent par diverger, et c'est celui qu'on relit le
// moins qui devient faux.
//
// ## Aucune clé nulle part
//
// La tentation est de coller la clé de `ont-app` dans un secret GitHub. C'est
// une clé **longue durée** : elle vaut tant qu'on ne la révoque pas, elle
// traîne dans les journaux d'un job mal écrit, et elle survit à la personne
// qui l'a posée.
//
// L'OIDC fait autrement. GitHub signe un jeton qui dit « je suis le workflow
// de telle branche de tel dépôt » ; AWS le vérifie contre la clé publique de
// GitHub et prête ce rôle **pour la durée du job**. Rien à stocker, rien à
// faire tourner, rien à révoquer.
//
// ## La condition sur `sub` est la serrure
//
// Sans elle, n'importe quel dépôt GitHub du monde pourrait emprunter ce rôle :
// le fournisseur ne dit que « ce jeton vient bien de GitHub Actions ». C'est la
// condition qui dit **lequel**.
//
// Épinglée à `refs/heads/main`. Une branche de travail, une pull request, un
// fork : rien de tout ça ne peut déployer.
//
// Les deux formes du sujet sont admises — GitHub a commencé à émettre des
// sujets **immuables**, avec les identifiants numériques insérés :
//
//     repo:ONTBible@316155655/ONTBibleApp@1331899040:ref:refs/heads/main
//
// Son API annonce pourtant l'inverse ; c'est le jeton livré au job qui fait
// foi. Une politique qui n'attend que l'ancienne forme refuse tout sans jamais
// dire pourquoi — STS répond « Not authorized », sans nommer la condition qui
// a manqué. Ce n'est pas un élargissement : deux chaînes exactes, sans joker,
// pour le même dépôt et la même branche.

// Le fournisseur existe déjà sur ce compte — AWS n'en accepte qu'un par
// émetteur, et le site l'a créé avant nous. On le référence, on ne le recrée
// pas.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

variable "depot_ci" {
  description = "Le dépôt GitHub autorisé à déployer le backend."
  type        = string
  default     = "ONTBible/ONTBibleApp"
}

// La même paire, sous la forme immuable. Les identifiants se relèvent une fois :
//
//     gh api orgs/ONTBible --jq .id
//     gh api repos/ONTBible/ONTBibleApp --jq .id
variable "depot_ci_immuable" {
  description = "Le même dépôt, sous la forme proprietaire@id/nom@id."
  type        = string
  default     = "ONTBible@316155655/ONTBibleApp@1331899040"
}

resource "aws_iam_role" "ci" {
  name = "ont-api-github"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          // Une liste vaut un « ou » : le jeton doit porter l'une des deux.
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.depot_ci_immuable}:ref:refs/heads/main",
            "repo:${var.depot_ci}:ref:refs/heads/main",
          ]
        }
      }
    }]
  })
}

// Le strict nécessaire pour remplacer du **code**, et rien pour changer
// l'infrastructure.
//
// C'est le même partage que pour le site, et il a la même raison : l'état de
// Terraform vit en local. Un job qui l'exécuterait travaillerait sans savoir ce
// qui existe déjà — il recréerait tout, ou détruirait ce qu'il ne connaît pas.
// La CI remplace du code ; la forme de l'infrastructure reste une décision
// prise à la main.
//
// Ce que ce rôle **ne peut pas** faire, et c'est ce qui compte ici : lire la
// table DynamoDB, où vivent les surlignages et la position de lecture — donnée
// de l'article 9. Toucher aux variables d'environnement, où vit le secret des
// jetons. Modifier la passerelle. Un jeton volé pendant la durée d'un job ne
// donnerait que le droit de poser un binaire dans cette fonction-ci.
resource "aws_iam_role_policy" "ci" {
  name = "deployer"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LeCodeDeLaLambda"
      Effect = "Allow"
      // `UpdateFunctionCode` seulement. Pas `UpdateFunctionConfiguration` : la
      // mémoire, le délai et les variables d'environnement sont décrits par
      // Terraform, et un job qui pourrait les changer les ferait diverger de ce
      // que le dépôt déclare. Le secret des jetons y vit, du reste.
      //
      // `GetFunctionConfiguration` est en revanche nécessaire, et ne donne que
      // la lecture. Après un `update-function-code`, la Lambda reste quelques
      // secondes en `InProgress` ; le job attend qu'elle en sorte
      // (`wait function-updated`), et cette attente interroge précisément cette
      // API. Sans elle, le déploiement échoue **après** avoir remplacé le code
      // — au pire endroit, la production déjà changée et le job rouge.
      Action = [
        "lambda:UpdateFunctionCode",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
      ]
      Resource = aws_lambda_function.api.arn
    }]
  })
}

output "role_ci" {
  description = "Le rôle à donner au workflow GitHub."
  value       = aws_iam_role.ci.arn
}
