#!/usr/bin/env bash
#
# Installe et lance La Bible ONT sur l'iPhone, dès qu'il est joignable.
#
#   ./scripts/lancer-sur-iphone.sh
#
# Attend l'appareil, l'installe, la lance. Ctrl-C pour abandonner.

set -euo pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.labibleont.ONT"

vert=$'\033[32m'; gris=$'\033[90m'; fin=$'\033[0m'

# On cherche l'iPhone physique — par le JSON, pas par la position des colonnes.
#
# La version précédente lisait le 4ᵉ champ en partant de la fin du tableau
# texte. Le nom de l'appareil y figure sans guillemets : dès qu'il contient
# des espaces, le décompte se décale et le script extrayait « 17 », pris dans
# « iPhone 17 Pro ». `devicectl --device 17` échouait, et la boucle attendait
# indéfiniment un appareil qu'elle avait sous les yeux.
INVENTAIRE="$(mktemp)"
trap 'rm -f "$INVENTAIRE"' EXIT

appareil() {
  xcrun devicectl list devices --json-output "$INVENTAIRE" >/dev/null 2>&1 || return 1
  python3 - "$INVENTAIRE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    devices = json.load(f)['result']['devices']
for d in devices:
    materiel = d.get('hardwareProperties', {})
    lien = d.get('connectionProperties', {})
    if (materiel.get('deviceType') == 'iPhone'
            and materiel.get('reality') == 'physical'
            and lien.get('tunnelState') != 'unavailable'):
        print(d['identifier'], d.get('deviceProperties', {}).get('name', ''), sep='\t')
        break
PY
}

printf '%sEn attente de l'\''iPhone…%s\n' "$gris" "$fin"
printf '%s  Branchez-le en USB, déverrouillez-le, et acceptez « Se fier » si demandé.%s\n\n' "$gris" "$fin"

essais=0
while true; do
  ligne="$(appareil || true)"
  id="${ligne%%$'\t'*}"
  nom="${ligne#*$'\t'}"
  if [ -n "$id" ] && xcrun devicectl device info details --device "$id" >/dev/null 2>&1; then
    break
  fi
  essais=$((essais + 1))
  # Attendre en silence, c'est indistinguable d'un script bloqué. Au bout de
  # trente secondes, on dit ce qu'on voit.
  if [ $((essais % 10)) -eq 0 ]; then
    printf '%s  toujours rien après %ss — appareils vus :%s\n' "$gris" "$((essais * 3))" "$fin"
    xcrun devicectl list devices 2>/dev/null | tail -n +3 | sed 's/^/    /'
  fi
  sleep 3
done

printf '%s✓%s appareil joignable — %s\n' "$vert" "$fin" "${nom:-$id}"

# On recompile **toujours**. La version précédente sautait cette étape dès
# que le `.app` existait — donc elle réinstallait indéfiniment le build de la
# première fois, sans jamais dire qu'elle le faisait. Une compilation
# incrémentale sans changement coûte quelques secondes ; installer une vieille
# app en croyant tester la nouvelle coûte une soirée.
echo "→ compilation"
cd "$RACINE/app"
xcodebuild -project ONT.xcodeproj -scheme ONT \
  -destination 'generic/platform=iOS' -configuration Debug build \
  -allowProvisioningUpdates >/dev/null

# Le chemin du produit est demandé à Xcode, pas deviné : le nom du dossier
# DerivedData porte un condensat qui change si le projet est déplacé.
APP="$(xcodebuild -project ONT.xcodeproj -scheme ONT \
        -destination 'generic/platform=iOS' -configuration Debug \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')/ONT.app"
[ -d "$APP" ] || { echo "compilation sans produit : $APP" >&2; exit 1; }
printf '%s✓%s compilée — %s\n' "$vert" "$fin" "$(du -sh "$APP" | cut -f1)"

echo "→ installation"
xcrun devicectl device install app --device "$id" "$APP" >/dev/null
printf '%s✓%s installée\n' "$vert" "$fin"

echo "→ lancement"
# `--terminate-existing` : sans lui, une instance déjà ouverte reste en place
# et le lancement ne fait rien de visible — on croit tester la nouvelle
# version alors qu'on regarde l'ancienne, encore en mémoire.
# `--activate` la ramène au premier plan, pour ne pas avoir à la chercher.
xcrun devicectl device process launch \
  --device "$id" --terminate-existing --activate "$BUNDLE" >/dev/null
printf '%s✓%s lancée au premier plan\n\n' "$vert" "$fin"

cat <<'TXT'
  À essayer :
    Vous → Continuer avec Apple     (Face ID, sans navigateur)
    Vous → Continuer avec Google    (page web)
    Vous → Continuer avec GitHub    (page web)

  Pour suivre ce que voit le serveur, dans un autre terminal :
    AWS_PROFILE=ont aws logs tail /aws/lambda/ont-api --follow
TXT
