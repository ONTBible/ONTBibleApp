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
# | simulateur | taille | pourquoi |
# |---|---|---|
# | `ONT Pro Max` | 1320 × 2868 | obligatoire ; Apple redimensionne pour les écrans plus petits |
# | `ONT iPadOS` | 2064 × 2752 | obligatoire, l'app visant `TARGETED_DEVICE_FAMILY: "1,2"` |
#
# Ce sont les simulateurs de la machine, réutilisés et démarrés au besoin — pas
# des jetables créés à côté. `ONT` n'y figure pas : c'est un iPhone 17 Pro, il
# rend 1206 × 2622, et l'App Store refuse cette taille. `scripts/simulateur.py`
# le vérifie sur une vraie capture avant que rien ne soit construit.
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

# Le simulateur des captures — **le tien**, pas un jetable.
#
# ## Pourquoi on réutilise les simulateurs nommés
#
# Le script créait « Captures 6.9 » et « Captures 13 » à côté de `ONT` et
# `ONT iPadOS`, qui existaient déjà et servaient au développement. Deux
# appareils de plus par machine, chacun avec son conteneur de plusieurs
# gigaoctets, pour rendre exactement ce que les tiens rendent.
#
# On prend donc les tiens, et on les démarre s'ils sont éteints.
#
# ## Pourquoi on vérifie quand même la taille de la dalle
#
# Parce qu'un nom ne dit pas une résolution. `ONT` est un iPhone 17 Pro : il
# rend 1206 × 2622, quand l'emplacement 6,9″ de l'App Store n'accepte que
# 1320 × 2868. Une capture à la mauvaise taille est refusée au téléversement,
# à la fin d'une chaîne de plusieurs minutes — ou pire, passe et déforme la
# vitrine.
#
# La mesure est prise sur une **vraie capture**, la seule qui ne puisse pas
# mentir là où un nom de type d'appareil peut tromper. Et elle est prise
# **avant** de rien construire : c'est la leçon des trois pannes précédentes,
# ce qui n'est pas vérifié tôt se découvre tard et à l'aveugle.
simulateur() {
  python3 "$(dirname "$0")/simulateur.py" "$1" "$2" "$3"
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

  # L'onglet, remis sur Bible.
  #
  # Le routeur retient le dernier onglet ouvert dans `UserDefaults` — utile
  # pour un lecteur, ruineux pour une vitrine : `ONT iPadOS` avait servi au
  # développement avec le Lexique ouvert, et la première affiche montrait donc
  # le Lexique là où elle doit montrer le corpus.
  #
  # Les trois autres écrans ne craignent rien, ils sont ouverts par un lien qui
  # impose son onglet. Seul le premier dépendait de l'état de la machine, et
  # c'est exactement le genre de dépendance qu'une capture ne doit pas avoir.
  #
  # La clé est **supprimée** plutôt que réécrite : le routeur retombe alors sur
  # son défaut, et on ne code pas ici une valeur qu'il faudrait suivre s'il
  # changeait d'avis.
  conteneur=$(xcrun simctl get_app_container "$sim" "$BUNDLE" data 2>/dev/null || true)
  if [ -n "$conteneur" ]; then
    /usr/libexec/PlistBuddy -c "Delete :tab" \
      "$conteneur/Library/Preferences/$BUNDLE.plist" >/dev/null 2>&1 || true
  fi

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
# `-print -quit` plutôt que `| head -1` : `find` s'arrête lui-même au premier
# résultat, au lieu d'être tué en écrivant dans un tuyau que `head` vient de
# fermer. Sous `set -o pipefail`, cette mort rend 141 et **abandonne le
# script** — mais seulement quand `find` a encore de quoi écrire après le
# premier résultat, donc jamais sur un dossier neuf et toujours sur un vieux.
APP=$(find /tmp/ont-captures-dd/Build/Products -name "ONT.app" -maxdepth 3 -print -quit)

etape "iPhone 6,9″"
serie "$(simulateur 'ONT Pro Max' 1320 2868)" "iphone-6.9"

etape "iPad 13″"
serie "$(simulateur 'ONT iPadOS' 2064 2752)" "ipad-13"

# Ce qu'on téléverse n'est pas ce qu'on vient de prendre. Les captures brutes
# restent dans `brut/` ; `vitrine.py` en fait les affiches. Enchaîné ici, et
# pas laissé à la main : une capture refaite sans son affiche remet la fiche
# dans l'état qu'on essaie de quitter.
etape "Les affiches"
./scripts/vitrine.py

printf '\n\033[1m%s\033[0m\n' "→ app/Captures"
