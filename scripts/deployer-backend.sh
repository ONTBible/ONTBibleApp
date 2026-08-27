#!/usr/bin/env bash
#
# Déploie la Lambda, en laissant à Sentry de quoi lire une panique.
#
#   ./scripts/deployer-backend.sh
#
# ## Pourquoi ce script existe plutôt qu'un `cargo lambda build && terraform apply`
#
# Un binaire Rust dépouillé ne dit plus le nom de ses fonctions : une panique
# arriverait dans Sentry en adresses hexadécimales. Mais le garder bavard coûte
# 11 Mo sur chaque démarrage à froid (24,3 Mo contre 13,2), et l'éditeur de
# liens de cargo-lambda n'offre aucun intermédiaire — `strip = "debuginfo"`
# dépouille autant que `strip = true`, c'est mesuré.
#
# La sortie est de faire les deux à la fois : on construit **complet**, on
# téléverse les symboles vers Sentry, puis on déploie une **copie dépouillée**.
# Sentry symbolise côté serveur. C'est exactement le mécanisme des dSYM d'iOS,
# et il tient à une vérification : l'identifiant de débogage est dérivé du code
# machine, pas de la table des symboles — il survit donc au dépouillement.
#
#     complet     24 321 856 o   Debug ID 3b687dd2-d5be-7e30-a257-74cdb38a39b6
#     dépouillé   13 155 432 o   Debug ID 3b687dd2-d5be-7e30-a257-74cdb38a39b6
#
# Si un jour les deux identifiants divergent, le contrôle plus bas échoue et
# le déploiement s'arrête : mieux vaut ne pas déployer que déployer aveugle.

set -euo pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

export SENTRY_ORG="${SENTRY_ORG:-pinkha-app}"
export SENTRY_PROJECT="${SENTRY_PROJECT:-ont-api}"

gras=$'\033[1m'; vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
titre() { printf '\n%s── %s ──%s\n' "$gras" "$1" "$fin"; }
ok()    { printf '%s✓%s %s\n' "$vert" "$fin" "$1"; }
ko()    { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; }
note()  { printf '%s  %s%s\n' "$gris" "$1" "$fin"; }

OBJCOPY="$(command -v llvm-objcopy || echo "$(brew --prefix llvm 2>/dev/null)/bin/llvm-objcopy")"
[ -x "$OBJCOPY" ] || { ko "llvm-objcopy introuvable — brew install llvm"; exit 1; }
command -v sentry-cli >/dev/null || { ko "sentry-cli introuvable — brew install getsentry/tools/sentry-cli"; exit 1; }

CIBLE="$RACINE/backend/target/lambda/ont-backend"

# ── 1. Construction, symboles compris ────────────────────────────────────────
titre "Construction"
cd "$RACINE/backend"
cargo lambda build --release --arm64
ok "$(du -h "$CIBLE/bootstrap" | cut -f1) — avec table des symboles"

# ── 2. Les symboles partent chez Sentry ──────────────────────────────────────
titre "Symboles → Sentry"
sentry-cli debug-files upload --include-sources --force-foreground "$CIBLE/bootstrap"

# ── 3. La copie dépouillée, c'est elle qu'on déploie ─────────────────────────
titre "Dépouillement"
# La sortie est capturée entière avant d'être filtrée : un `awk … exit` ferme
# le tuyau, et sentry-cli panique sur l'écriture suivante au lieu de répondre.
identifiant() {
  local sortie
  sortie="$(sentry-cli debug-files check "$1")"
  # `$NF` et non `$3` : la ligne est « > Debug ID: <uuid> », l'identifiant est
  # le dernier champ. Avec `$3` la fonction renvoyait « ID: » des deux côtés —
  # une comparaison toujours vraie, donc un contrôle qui ne contrôlait rien.
  printf '%s\n' "$sortie" | grep -m1 'Debug ID:' | awk '{print $NF}'
}

AVANT="$(identifiant "$CIBLE/bootstrap")"
cp "$CIBLE/bootstrap" "$CIBLE/bootstrap.strip"
"$OBJCOPY" --strip-all "$CIBLE/bootstrap.strip"
APRES="$(identifiant "$CIBLE/bootstrap.strip")"

if [ "$AVANT" != "$APRES" ]; then
  ko "l'identifiant de débogage a changé au dépouillement :"
  ko "  complet   $AVANT"
  ko "  dépouillé $APRES"
  note "Sentry ne pourrait pas apparier les symboles. Déploiement interrompu."
  exit 1
fi
ok "$(du -h "$CIBLE/bootstrap.strip" | cut -f1) — identifiant inchangé ($AVANT)"

# `bootstrap` est le nom attendu par le runtime Lambda, et le bit exécutable
# doit survivre à l'archivage : la copie dépouillée entre donc sous ce nom-là,
# depuis un répertoire à part pour ne pas piétiner le binaire complet.
BOITE="$(mktemp -d)"
trap 'rm -rf "$BOITE"' EXIT
cp "$CIBLE/bootstrap.strip" "$BOITE/bootstrap"
chmod +x "$BOITE/bootstrap"
( cd "$BOITE" && zip -q -9 bootstrap.zip bootstrap )
mv "$BOITE/bootstrap.zip" "$CIBLE/bootstrap.zip"
rm -f "$CIBLE/bootstrap.strip"
ok "archive prête"

if [ "${1:-}" = "--sans-deploiement" ]; then
  note "--sans-deploiement : on s'arrête avant terraform."
  exit 0
fi

# ── 4. Déploiement ───────────────────────────────────────────────────────────
titre "Déploiement"
cd "$RACINE/backend/terraform"
source ./secrets.env
source ./oauth.env

export TF_VAR_apple_client_id="$APPLE_CLIENT_ID"
export TF_VAR_apple_team_id="$APPLE_TEAM_ID"
export TF_VAR_apple_key_id="$APPLE_KEY_ID"
# **Une clé absente doit arrêter le déploiement, pas le traverser.**
#
# `$(cat fichier-absent)` rend une chaîne vide sans faire échouer quoi que ce
# soit : Terraform pousse alors une variable vide, la Lambda part avec, et Sign
# in with Apple cesse de fonctionner en production — sans une ligne d'erreur.
#
# C'est arrivé le 21 août 2026. La clé avait simplement été rangée de
# `CloudDocs/Downloads/` vers `CloudDocs/Secrets/`, et le déploiement a
# continué comme si de rien n'était.
verifier_cle() {
  local chemin="${1/#\~/$HOME}" quoi="$2"
  if [ ! -r "$chemin" ]; then
    echo "  ✗ $quoi : clé illisible ou absente — $chemin" >&2
    echo "    Déployer maintenant écraserait la valeur en production par du vide." >&2
    exit 1
  fi
  cat "$chemin"
}

export TF_VAR_apple_private_key="$(verifier_cle "$APPLE_KEY_PATH" "Sign in with Apple")"
export TF_VAR_google_client_id="$GOOGLE_CLIENT_ID"
export TF_VAR_google_client_secret="$GOOGLE_CLIENT_SECRET"
# APNs. Facultatif : sans ces valeurs, la diffusion reste éteinte et le
# backend se déploie normalement. `:-` plutôt qu'une erreur, parce qu'un
# backend sans notifications reste un backend qui marche.
# **Le DSN de Sentry, qui n'était posé nulle part.**
#
# La variable Terraform vaut `""` par défaut : chaque déploiement écrasait donc
# la valeur en production, et le backend cessait de remonter ses erreurs. Le
# projet `ont-api` avait reçu un événement le 12 août — renseigné à la main —
# puis le déploiement suivant l'a effacé, en silence.
#
# C'est ce qui a rendu invisible la panne de Sign in with Apple du 21 août : le
# backend ne pouvait rien signaler.
export TF_VAR_sentry_dsn="${SENTRY_DSN:-}"
export TF_VAR_apns_team_id="${APNS_TEAM_ID:-}"
export TF_VAR_apns_key_id="${APNS_KEY_ID:-}"
# APNs, lui, reste facultatif : sans chemin, la diffusion est éteinte et c'est
# un état valide. Mais un chemin **renseigné et illisible** est une erreur, pas
# une absence — on ne peut pas la distinguer d'un secret perdu.
export TF_VAR_apns_private_key="$([ -n "${APNS_KEY_PATH:-}" ] && verifier_cle "$APNS_KEY_PATH" "APNs" || echo "")"
export TF_VAR_apns_topic="${APNS_TOPIC:-com.labibleont.ONT}"
export TF_VAR_apns_sandbox_key_id="${APNS_SANDBOX_KEY_ID:-}"
export TF_VAR_apns_sandbox_private_key="$([ -n "${APNS_SANDBOX_KEY_PATH:-}" ] && verifier_cle "$APNS_SANDBOX_KEY_PATH" "APNs sandbox" || echo "")"
export TF_VAR_secret_diffusion="${SECRET_DIFFUSION:-}"
export TF_VAR_github_client_id="$GITHUB_CLIENT_ID"
export TF_VAR_github_client_secret="$GITHUB_CLIENT_SECRET"
# L'identité du site chez Apple. Facultative — tant qu'elle manque, le backend
# dit « fournisseur non configuré » au lieu de présenter l'App ID à un code
# accordé au Services ID et de recevoir un `invalid_grant` qu'on chercherait
# chez le site.
export TF_VAR_apple_services_id="${APPLE_SERVICES_ID:-}"

terraform apply -auto-approve -no-color | tail -3

# **Vérifier l'arrivée, pas seulement le départ.**
#
# Tout ce qui précède garde le *départ* : les chemins de clés sont contrôlés, la
# précondition Terraform refuse un apply lancé sans `oauth.env`. Rien ne
# regardait ce qui est **réellement en ligne** une fois l'apply rendu — et les
# trois pannes de ce backend se ressemblent toutes : une variable partie vide,
# aucune erreur, et la découverte des semaines plus tard.
#
# Le contrôle lit la configuration de la fonction déployée et rend 1 si une
# variable nécessaire est vide. Il ne lit jamais une valeur.
"$RACINE/scripts/eprouver-le-backend.sh"
ok "déployé"
