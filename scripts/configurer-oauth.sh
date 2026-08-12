#!/usr/bin/env bash
#
# Branche les identifiants OAuth de bout en bout.
#
# Votre part : coller huit valeurs. Le script fait le reste — vérifier leur
# forme, déployer la Lambda, poser les identifiants publics dans l'app,
# régénérer le projet, et contrôler que les trois fournisseurs répondent.
#
#   ./scripts/configurer-oauth.sh
#
# Relançable : les valeurs déjà saisies sont proposées par défaut, il suffit
# d'appuyer sur Entrée pour les garder.

set -euo pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$RACINE/backend/terraform/oauth.env"
API="https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com"

gras=$'\033[1m'; vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'

titre() { printf '\n%s── %s ──%s\n' "$gras" "$1" "$fin"; }
ok()    { printf '%s✓%s %s\n' "$vert" "$fin" "$1"; }
ko()    { printf '%s✗%s %s\n' "$rouge" "$fin" "$1"; }
note()  { printf '%s  %s%s\n' "$gris" "$1" "$fin"; }

[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Déjà connus : l'App ID a été enregistré par Xcode, avec la capacité
# « Sign in with Apple » activée, et le Team ID vient du certificat de
# signature présent sur cette machine.
: "${APPLE_CLIENT_ID:=com.labibleont.ONT}"
: "${APPLE_TEAM_ID:=N49VNC2G57}"

# demander <variable> <intitulé> <indice> [motif]
demander() {
  local var="$1" intitule="$2" indice="$3" motif="${4:-.}"
  local actuel="${!var:-}" saisie

  # Déjà renseignée et bien formée : on ne dérange pas.
  if [ -n "$actuel" ] && printf '%s' "$actuel" | grep -qE "$motif"; then
    ok "$intitule — repris du fichier"
    return
  fi

  while true; do
    if [ -n "$actuel" ]; then
      printf '%s\n%s  [%s]%s\n> ' "$intitule" "$gris" "${actuel:0:28}…" "$fin"
    else
      printf '%s\n%s  %s%s\n> ' "$intitule" "$gris" "$indice" "$fin"
    fi
    read -r saisie
    saisie="${saisie:-$actuel}"

    if [ -z "$saisie" ]; then
      ko "valeur requise"
      continue
    fi
    if ! printf '%s' "$saisie" | grep -qE "$motif"; then
      ko "forme inattendue — attendu : $indice"
      continue
    fi
    printf -v "$var" '%s' "$saisie"
    return
  done
}

cat <<'TXT'

  Configuration OAuth de La Bible ONT
  ───────────────────────────────────
  Marche à suivre détaillée : docs/comptes-oauth.md

TXT

titre "Apple"
note "Pas de Services ID : le flux natif utilise l'identifiant de l'app."
demander APPLE_CLIENT_ID "Identifiant de l'app" "com.labibleont.ONT" '^[a-zA-Z0-9.-]+$'
demander APPLE_TEAM_ID   "Team ID"              "10 caractères"       '^[A-Z0-9]{10}$'
demander APPLE_KEY_ID    "Key ID de la clé"     "10 caractères"       '^[A-Z0-9]{10}$'

# La clé est lue depuis son chemin — son contenu ne transite jamais par
# l'affichage, ni par un copier-coller.
lire_cle() {
  local chemin="${1/#\~/$HOME}"
  APPLE_KEY_PATH="$chemin"
  if [ -n "$chemin" ] && [ -f "$chemin" ] && grep -q "BEGIN PRIVATE KEY" "$chemin"; then
    APPLE_PRIVATE_KEY="$(cat "$chemin")"
    ok "clé lue depuis $(basename "$chemin")"
    return 0
  fi
  return 1
}

if ! lire_cle "${APPLE_KEY_PATH:-}"; then
  while true; do
    printf 'Chemin du fichier .p8\n%s  ~/Downloads/AuthKey_XXXXXXXXXX.p8%s\n> ' "$gris" "$fin"
    read -r chemin
    lire_cle "$chemin" && break
    ko "fichier introuvable, ou ce n'est pas une clé PEM"
  done
fi

titre "Google"
note "Client de type « Application Web » — surtout pas « iOS » : ce dernier"
note "n'a pas de secret, et toute l'architecture repose dessus."
demander GOOGLE_CLIENT_ID     "Client ID"     "…apps.googleusercontent.com" 'apps\.googleusercontent\.com$'
demander GOOGLE_CLIENT_SECRET "Client secret" "GOCSPX-…"                    '^.{8,}$'

titre "GitHub"
demander GITHUB_CLIENT_ID     "Client ID"     "Ov23li… ou Iv1.…" '^.{8,}$'
demander GITHUB_CLIENT_SECRET "Client secret" "40 caractères"    '^.{20,}$'

# ── Sauvegarde ───────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$ENV_FILE")"
{
  echo "# Identifiants OAuth — gitignoré. Ne jamais committer."
  echo "# Généré le $(date +%F)."
  for v in APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_KEY_PATH \
           GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET \
           GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET; do
    printf '%s=%q\n' "$v" "${!v}"
  done
  # Le contenu de la clé n'est jamais recopié : seul son chemin l'est. Moins
  # il existe d'exemplaires d'une clé privée sur le disque, mieux c'est.
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok "identifiants rangés dans backend/terraform/oauth.env (chmod 600, gitignoré)"

# ── Déploiement ──────────────────────────────────────────────────────────────
titre "Déploiement de la Lambda"
cd "$RACINE/backend/terraform"
source ./secrets.env

export TF_VAR_apple_client_id="$APPLE_CLIENT_ID"
export TF_VAR_apple_team_id="$APPLE_TEAM_ID"
export TF_VAR_apple_key_id="$APPLE_KEY_ID"
export TF_VAR_apple_private_key="$APPLE_PRIVATE_KEY"
export TF_VAR_google_client_id="$GOOGLE_CLIENT_ID"
export TF_VAR_google_client_secret="$GOOGLE_CLIENT_SECRET"
export TF_VAR_github_client_id="$GITHUB_CLIENT_ID"
export TF_VAR_github_client_secret="$GITHUB_CLIENT_SECRET"

terraform apply -auto-approve -no-color | tail -3

# ── Côté app ─────────────────────────────────────────────────────────────────
titre "Identifiants publics dans l'app"
cd "$RACINE/app"
python3 - "$GOOGLE_CLIENT_ID" "$GITHUB_CLIENT_ID" <<'PY'
import pathlib, re, sys

google, github = sys.argv[1], sys.argv[2]
p = pathlib.Path('project.yml')
s = p.read_text()
s = re.sub(r'ONTGoogleClientID: ".*"', f'ONTGoogleClientID: "{google}"', s)
s = re.sub(r'ONTGitHubClientID: ".*"', f'ONTGitHubClientID: "{github}"', s)
p.write_text(s)
PY
ok "posés dans project.yml (publics : ils voyagent dans l'URL d'autorisation)"

xcodegen generate >/dev/null
ok "projet régénéré"

# ── Contrôle ─────────────────────────────────────────────────────────────────
titre "Contrôle"
note "Un code bidon doit donner 401 « connexion refusée » : le fournisseur a"
note "répondu et a dit non. Un 502 signifierait qu'il n'est pas joignable."

for p in apple google github; do
  reponse=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/auth/$p" \
    -H 'content-type: application/json' \
    -d '{"code":"code-invalide","redirect_uri":"'"$API"'/auth/'"$p"'/callback"}')
  case "$reponse" in
    401) ok "$p — le fournisseur répond" ;;
    502) ko "$p — injoignable : vérifiez les identifiants" ;;
    *)   ko "$p — HTTP $reponse (inattendu)" ;;
  esac
done

cat <<TXT

  ${vert}Terminé.${fin}

  Dans l'app : onglet Vous → Continuer avec…

TXT
