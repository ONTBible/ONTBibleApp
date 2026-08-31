#!/usr/bin/env bash
#
# Construit la liseuse du Mac et la lance, sans passer par TestFlight.
#
#   ./scripts/lancer-sur-le-mac.sh            # construit, embarque, lance
#   ./scripts/lancer-sur-le-mac.sh --sans-vault  # sans le pipeline
#
# ## Pourquoi ne pas simplement pousser sur `dev`
#
# Apple limite les téléversements **par application, par plateforme et par
# jour**. Le 31 août 2026, seize builds iOS l'ont épuisé, et c'est la livraison
# qui comptait — la promotion vers la bêta — qui s'est fait refuser :
#
#     Upload limit reached. […] Please wait 1 day and try again.
#
# Chaque poussée réflexe sur `dev` consomme une place et la perd pour un build
# qui la méritait. On vérifie donc ici, sur la machine, et l'on ne fusionne dans
# `dev` que ce qui est fini.
#
# C'est le pendant de `lancer-sur-iphone.sh`, qui fait la même chose pour le
# téléphone et pour la même raison.
#
# ## Ce qu'il fait de plus qu'un build
#
# Il **embarque le pipeline**, sans quoi le mode vault ne peut pas relire les
# brouillons — c'est le premier usage de ce script. `--sans-vault` l'évite quand
# on veut voir exactement ce que reçoit un testeur du canal bêta, qui ne l'a pas.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
echec() { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; exit 1; }

AVEC_VAULT=1
for arg in "$@"; do
  case "$arg" in
    --sans-vault) AVEC_VAULT=0 ;;
    *) echec "argument inconnu : « $arg »" ;;
  esac
done

DD="${TMPDIR:-/tmp}/dd-ont-mac"
XCODE=$(xcodebuild -version)
echo "${gris}→ ${XCODE%%$'\n'*}${fin}"

echo "→ le projet"
(cd app && xcodegen generate >/dev/null)

echo "→ la compilation"
if ! xcodebuild build \
      -project app/ONT.xcodeproj -scheme ONTMac -destination 'platform=macOS' \
      -derivedDataPath "$DD" -allowProvisioningUpdates \
      > "${TMPDIR:-/tmp}/ont-mac-build.log" 2>&1; then
  echec "la compilation échoue — voir ${TMPDIR:-/tmp}/ont-mac-build.log"
fi

APP=$(find "$DD/Build/Products" -maxdepth 3 -name "*.app" -print -quit)
[ -n "$APP" ] || echec "aucune app produite"

if [ "$AVEC_VAULT" -eq 1 ]; then
  echo "→ le pipeline, pour le mode vault"
  ./scripts/embarquer-le-pipeline.sh "$APP" | sed 's/^/  /'
else
  echo "${gris}  sans pipeline — le menu « Suivre un vault… » sera absent,"
  echo "  comme dans un build du canal bêta${fin}"
fi

# **On ferme celle qui tourne avant d'ouvrir la neuve.** Sinon `open` ramène
# l'ancienne au premier plan et l'on croit avoir lancé la nouvelle — la même
# famille d'erreur que tout le reste de cette journée.
pkill -f "La Bible ONT" 2>/dev/null || true
sleep 1

open "$APP"
printf '%s✓%s lancée depuis %s\n' "$vert" "$fin" "$APP"
