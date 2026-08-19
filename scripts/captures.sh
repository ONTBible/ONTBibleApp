#!/usr/bin/env bash

# Les captures d'écran pour l'App Store.
#
#     ./scripts/captures.sh
#
# ## Pourquoi un script et pas quelques captures à la main
#
# Une capture reprise à la main après chaque changement visuel finit par montrer
# une version qui n'existe plus : on refait celle qui saute aux yeux, on oublie
# les trois autres, et la fiche de l'App Store devient un collage de trois
# époques. Ici, une commande les refait toutes.
#
# ## Les deux tailles qu'Apple exige
#
# | appareil | taille | pourquoi |
# |---|---|---|
# | iPhone 6,9″ | 1320 × 2868 | obligatoire ; Apple redimensionne pour les écrans plus petits |
# | iPad 13″ | 2064 × 2752 | obligatoire, l'app visant `TARGETED_DEVICE_FAMILY: "1,2"` |
#
# ## Comment l'app est conduite
#
# Par l'argument de lancement `-ouvrir`, pas par `simctl openurl`.
#
# La différence n'est pas cosmétique : un lien ouvert de l'extérieur déclenche
# une confirmation système — « Open in "La Bible ONT"? » — que `simctl` ne sait
# pas taper, et qui se retrouve au milieu de la capture. Pire, elle **survit aux
# relancements** : elle appartient à SpringBoard, pas à l'app, et il faut
# effacer le simulateur pour s'en débarrasser.
#
# L'argument de lancement, lui, passe par `openLaunchArgumentURL` et n'ouvre
# aucun dialogue.

set -euo pipefail

cd "$(dirname "$0")/.."

SORTIE="app/Captures/brut"
BUNDLE="com.labibleont.ONT"

# L'unité montrée est **verrouillée**. Bereshit 1 porte « Brouillon — en attente
# de validation » : honnête dans l'app, mal choisi pour une vitrine.
ECRANS=(
  ""                                # le corpus, les 70 livres
  "ont://read/bereshit/bereshit-3"  # la lecture, les trois niveaux
  "ont://term/elohim"               # une fiche d'intraduisible
  "ont://read/bereshit"             # la table d'un livre
)

etape() { printf '\n\033[1m── %s\033[0m\n' "$1"; }

# Le simulateur, créé s'il manque. Les images disponibles changent d'une version
# de Xcode à l'autre : on ne compte pas sur celles que la machine porte déjà.
#
# **Ni sur l'identifiant du type d'appareil.** Il n'est pas stable non plus :
# `…SimDeviceType.iPad-Pro-13-inch-M5` est devenu `…-M5-12GB` le jour où Apple
# a décliné l'iPad par quantité de mémoire, et le script est mort dessus. On
# donne donc un préfixe, et on retient le premier type qui commence par là.
simulateur() {
  local nom="$1" prefixe="$2" existant
  existant=$(xcrun simctl list devices -j \
    | python3 -c "
import json,sys
for liste in json.load(sys.stdin)['devices'].values():
    for d in liste:
        if d['name'] == '$nom':
            print(d['udid']); raise SystemExit
")
  if [ -z "$existant" ]; then
    local runtime type
    runtime=$(xcrun simctl list runtimes -j \
      | python3 -c "
import json,sys
ios=[r for r in json.load(sys.stdin)['runtimes'] if r['isAvailable'] and 'iOS' in r['name']]
print(sorted(ios, key=lambda r: r['version'])[-1]['identifier'])")
    type=$(xcrun simctl list devicetypes -j \
      | python3 -c "
import json,sys
noms=[t['identifier'] for t in json.load(sys.stdin)['devicetypes']
      if t['identifier'].startswith('$prefixe')]
if not noms:
    sys.exit('aucun type de simulateur ne commence par $prefixe')
print(sorted(noms)[0])")
    existant=$(xcrun simctl create "$nom" "$type" "$runtime")
  fi
  echo "$existant"
}

serie() {
  local sim="$1" dossier="$2"
  mkdir -p "$SORTIE/$dossier"

  xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1

  # Le simulateur en français. Il naît en anglais et n'hérite pas de la langue
  # de l'app : l'iPad affiche la date à côté de l'heure, et la vitrine d'une
  # app française portait « Wed 19 Aug ». Les préférences ne sont relues qu'au
  # démarrage, d'où le cycle d'arrêt.
  xcrun simctl spawn "$sim" defaults write "Apple Global Domain" \
    AppleLanguages -array fr-FR >/dev/null 2>&1 || true
  xcrun simctl spawn "$sim" defaults write "Apple Global Domain" \
    AppleLocale -string fr_FR >/dev/null 2>&1 || true
  xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1

  xcrun simctl install "$sim" "$APP"

  # La barre d'état, figée. Sans ça elle porte l'heure de la machine et une
  # jauge à moitié vide — deux détails qui datent la capture et trahissent
  # l'émulateur. 9:41 est l'heure des vitrines d'Apple depuis le premier iPhone.
  #
  # `discharging` et non `charged` : `charged` peint une pile **verte avec un
  # éclair**, la seule tache de couleur vive de l'affiche, et elle tombe dans
  # le cadre de l'appareil où l'œil va en premier.
  xcrun simctl status_bar "$sim" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100 >/dev/null 2>&1 || true

  local i=1
  for cible in "${ECRANS[@]}"; do
    xcrun simctl terminate "$sim" "$BUNDLE" >/dev/null 2>&1 || true
    sleep 2
    if [ -n "$cible" ]; then
      xcrun simctl launch "$sim" "$BUNDLE" -ouvrir "$cible" >/dev/null
    else
      xcrun simctl launch "$sim" "$BUNDLE" >/dev/null
    fi

    # Quatorze secondes. L'app analyse le corpus au premier lancement, et une
    # capture prise trop tôt rend un écran noir qui passe pour un défaut de
    # mise en page.
    sleep 14

    local f="$SORTIE/$dossier/$(printf '%02d' $i).png"
    xcrun simctl io "$sim" screenshot "$f" >/dev/null 2>&1

    # Une capture presque noire est une app qui n'avait pas fini de charger.
    # La laisser passer, c'est envoyer un écran vide à la revue d'Apple.
    python3 - "$f" <<'PY'
import sys
import numpy as np
from PIL import Image
im = Image.open(sys.argv[1])
lum = np.asarray(im.convert("L")).mean()
etat = "✓" if lum > 100 else "✗ ÉCRAN NOIR"
print(f"  {sys.argv[1]}  {im.size[0]}×{im.size[1]}  {etat}")
if lum <= 100:
    raise SystemExit(1)
PY
    i=$((i + 1))
  done
}

etape "Le corpus et le projet"
./scripts/corpus.sh >/dev/null

etape "L'app"
xcodebuild -project app/ONT.xcodeproj -scheme ONT \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ont-captures-dd build >/dev/null
APP=$(find /tmp/ont-captures-dd/Build/Products -name "ONT.app" -maxdepth 3 | head -1)

etape "iPhone 6,9″"
serie "$(simulateur 'Captures 6.9' com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max)" "iphone-6.9"

etape "iPad 13″"
serie "$(simulateur 'Captures 13' com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5)" "ipad-13"

# Ce qu'on téléverse n'est pas ce qu'on vient de prendre. Les captures brutes
# restent dans `brut/` ; `vitrine.py` en fait les affiches. Enchaîné ici, et
# pas laissé à la main : une capture refaite sans son affiche remet la fiche
# dans l'état qu'on essaie de quitter.
etape "Les affiches"
./scripts/vitrine.py

printf '\n\033[1m%s\033[0m\n' "→ app/Captures"
