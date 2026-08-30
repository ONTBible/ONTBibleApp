#!/usr/bin/env bash
#
# Dire si le backend en ligne a bien de quoi faire fonctionner la connexion.
#
# ## Pourquoi ce script existe
#
# Trois incidents, la même forme, et aucune alarme les trois fois.
#
# Le 21 août 2026, la clé de Sign in with Apple avait été rangée dans un autre
# dossier. `$(cat fichier-absent)` rend une chaîne vide sans faire échouer quoi
# que ce soit : Terraform a poussé une variable vide, la Lambda est partie avec,
# et la connexion Apple a cessé de marcher **en production, sans une ligne
# d'erreur**. Le DSN de Sentry a subi la même chose — écrasé par du vide à
# chaque déploiement —, ce qui a rendu la première panne invisible. Et un
# `terraform apply` lancé sans avoir sourcé `oauth.env` vide les huit variables
# OAuth d'un coup, sous la mention « 1 to change », au milieu d'un plan qui
# parlait d'autre chose.
#
# Des garde-fous ont été posés à chaque fois — une précondition Terraform, une
# vérification des chemins de clés dans `deployer-backend.sh`. Ils gardent tous
# le **départ**. Aucun ne regarde l'**arrivée** : `terraform apply` rend la main,
# le script affiche « déployé », et personne ne sait ce qui est réellement en
# ligne.
#
# ## Ce qu'il regarde, et pourquoi de l'extérieur
#
# La configuration de la fonction déployée, lue par l'API d'AWS — pas les
# fichiers locaux, pas le plan Terraform. Ce qui est en ligne, et rien d'autre.
#
# Sans ça, la seule façon de savoir si la connexion marche est **de se
# connecter** — et un échec n'apprend rien : le serveur répond « connexion
# refusée » aussi bien pour un code périmé que pour un secret manquant. Ces deux
# états sont indistinguables de l'extérieur.
#
# ## Il ne lit jamais une valeur
#
# Seulement si elle est vide ou non. Les secrets ne traversent ni la sortie, ni
# un journal, ni le presse-papiers de qui passe par là.
#
# Usage :
#     ./scripts/eprouver-le-backend.sh            la fonction de production
#     ./scripts/eprouver-le-backend.sh ont-api    une autre, si elle existe
#
# Rend 0 si tout ce qui est nécessaire est posé, 1 sinon — donc utilisable en
# fin de déploiement et dans un enchaînement.

set -euo pipefail

FONCTION="${1:-ont-api}"
REGION="${AWS_REGION:-eu-west-3}"

gras=$'\033[1m'; vert=$'\033[32m'; rouge=$'\033[31m'; jaune=$'\033[33m'; gris=$'\033[90m'; fin=$'\033[0m'
titre() { printf '\n%s── %s ──%s\n' "$gras" "$1" "$fin"; }
ok()    { printf '%s✓%s %s\n' "$vert" "$fin" "$1"; }
ko()    { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; }
note()  { printf '%s  %s%s\n' "$gris" "$1" "$fin"; }

command -v aws >/dev/null || { ko "aws introuvable — brew install awscli"; exit 1; }

titre "Le backend en ligne — $FONCTION ($REGION)"

CONFIG=$(aws lambda get-function-configuration \
  --region "$REGION" --function-name "$FONCTION" \
  --query 'Environment.Variables' --output json 2>&1) || {
    ko "la fonction est illisible — identifiants AWS absents, ou mauvaise région"
    note "$CONFIG"
    exit 1
  }

# **Le partage nécessaire / facultatif est celui de l'app, pas celui d'AWS.**
#
# Nécessaire = son absence casse quelque chose que le lecteur voit. Facultatif =
# son absence est un état valide, que le backend sait traiter — APNs éteint, la
# diffusion fermée. Sentry est à part : son absence ne casse rien pour le
# lecteur, et c'est bien le problème — elle éteint la seule chose qui aurait
# signalé les deux autres pannes.
NECESSAIRES="APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY
GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET
JWT_SECRET TABLE_NAME"
SURVEILLEES="SENTRY_DSN"

python3 - "$CONFIG" "$NECESSAIRES" "$SURVEILLEES" <<'PY'
import json, sys

variables = json.loads(sys.argv[1]) or {}
necessaires = sys.argv[2].split()
surveillees = sys.argv[3].split()

vert, rouge, jaune, gris, fin = "\033[32m", "\033[31m", "\033[33m", "\033[90m", "\033[0m"

manquantes, eteintes = [], []
for nom in necessaires:
    posee = bool(variables.get(nom, "").strip())
    if not posee:
        manquantes.append(nom)
    marque = f"{vert}✓{fin}" if posee else f"{rouge}✗{fin}"
    etat = "posée" if posee else "VIDE"
    print(f"  {marque} {nom:<24} {etat}")

for nom in surveillees:
    posee = bool(variables.get(nom, "").strip())
    if not posee:
        eteintes.append(nom)
    marque = f"{vert}✓{fin}" if posee else f"{jaune}!{fin}"
    print(f"  {marque} {nom:<24} {'posée' if posee else 'vide'}")

# Ce qui est là et qu'on n'attendait pas : ni faute ni alarme, mais le dire
# évite de croire la liste exhaustive le jour où une variable s'ajoute.
inconnues = sorted(set(variables) - set(necessaires) - set(surveillees))
if inconnues:
    print(f"\n{gris}  aussi posées : {', '.join(inconnues)}{fin}")

if eteintes:
    print(
        f"\n{jaune}!{fin} {', '.join(eteintes)} est vide — le backend ne remonte plus rien.\n"
        f"  C'est ce qui a rendu invisible la panne de connexion du 21 août 2026."
    )

if manquantes:
    print(
        f"\n{rouge}✗{fin} {len(manquantes)} variable(s) nécessaire(s) vide(s) : "
        f"{', '.join(manquantes)}\n"
        "  La connexion est cassée en production pour tout le monde.\n"
        "  Réparer : cd backend/terraform && ../../scripts/deployer-backend.sh\n"
        "  — c'est le seul chemin qui source `oauth.env`."
    )
    raise SystemExit(1)

print(f"\n{vert}✓{fin} tout ce qui est nécessaire est en place.")
PY
