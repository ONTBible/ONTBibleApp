#!/usr/bin/env bash
#
# Les captures d'écran du Mac, pour l'App Store.
#
#     ./scripts/captures-mac.sh
#
# ## Pourquoi il n'y a pas de simulateur ici
#
# Il n'existe **pas de simulateur macOS** — l'app y tourne nativement. La
# capture est donc celle de la vraie fenêtre, et c'est plus simple que sur
# l'iPhone, pas moins : rien à démarrer, rien à effacer.
#
# ## La taille, qui tombe juste
#
# Apple n'accepte que quatre tailles pour macOS : 1280 × 800, 1440 × 900,
# 2560 × 1600, 2880 × 1800. Une fenêtre de **1440 × 900 points** capturée sur un
# écran Retina rend **2880 × 1800** — une taille acceptée, sans redimensionner
# après coup. Redimensionner coûterait la netteté du texte, qui est tout ce que
# cette app montre.
#
# La fenêtre est posée par un **argument de lancement**, comme `captures.sh` le
# fait pour l'iPhone avec `-ouvrir`. Les deux autres voies sont fermées :
# `osascript` n'a pas l'accessibilité sur cette machine, et les préférences de
# cadre de SwiftUI sont des clés de neuf cents caractères qui portent l'arbre de
# vues entier.
#
# ## Ce que le script refuse de faire
#
# Il ne garde **aucune** capture dont la taille n'est pas exactement celle
# qu'Apple attend. Une image d'une taille voisine est rejetée au téléversement,
# et le découvrir là coûte le trajet entier.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
echec() { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; exit 1; }

SORTIE="app/Captures/mac"
TAILLE="1440x900"
ATTENDU_L=2880
ATTENDU_H=1800

# Les mêmes scènes que l'iPhone, pour que la fiche raconte la même chose.
# L'unité montrée est verrouillée : Bereshit 1 porte « Brouillon — en attente de
# validation », honnête dans l'app et mal choisi pour une vitrine.
#
# **La fiche d'intraduisible est en dernier, et ce n'est pas un goût.** Elle
# s'ouvre en feuille par-dessus la lecture, et **ne se ferme pas** quand on
# navigue ailleurs : dans le premier jet, elle était en troisième position et la
# quatrième capture la montrait encore, par-dessus la table du livre. Deux
# captures pour une scène, et la taille était juste dans les deux.
ECRANS=(
  ""                                # le corpus, les 70 livres
  "ont://read/bereshit/bereshit-3"  # la lecture, les trois niveaux
  "ont://read/bereshit"             # la table d'un livre
  "ont://term/elohim"               # une fiche d'intraduisible — en dernier
)

TRAVAIL=$(mktemp -d)
trap 'rm -rf "$TRAVAIL"' EXIT

# ── Le repéreur de fenêtre
#
# `System Events` est muet ici — l'accessibilité est refusée à `osascript` — et
# le serveur de fenêtres, lui, répond toujours.
cat > "$TRAVAIL/fenetre.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let liste = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for f in liste {
    guard let nom = f[kCGWindowOwnerName as String] as? String, nom.contains("Bible") else { continue }
    let b = f[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print("\(f[kCGWindowNumber as String] as? Int ?? -1)\t\(Int(b["Width"] ?? 0))\t\(Int(b["Height"] ?? 0))")
    break
}
SWIFT
swiftc -O "$TRAVAIL/fenetre.swift" -o "$TRAVAIL/fenetre" 2>/dev/null || echec "le repéreur ne compile pas"

# **On attend une géométrie plausible, on ne dort pas un temps fixe.**
#
# Stage Manager rend une fenêtre garée comme une **vignette en perspective** de
# 124 × 130, et `CGWindowList` rapporte la vignette comme si c'était la fenêtre.
# Une capture prise à ce moment-là est nette, de la bonne forme, et fausse. Ça a
# coûté une heure le 31 août 2026.
attendre_la_fenetre() {
    local i ligne largeur
    for i in $(seq 1 20); do
        sleep 1
        ligne=$("$TRAVAIL/fenetre" 2>/dev/null || true)
        largeur=$(printf '%s' "$ligne" | cut -f2)
        if [ -n "$largeur" ] && [ "$largeur" -ge 1400 ]; then
            printf '%s' "$ligne"; return 0
        fi
    done
    return 1
}

APP="${1:-}"
if [ -z "$APP" ]; then
  LISTE="$(ls -dt ~/Library/Developer/Xcode/DerivedData/ONT-*/Build/Products/Debug/*.app 2>/dev/null || true)"
  APP="${LISTE%%$'\n'*}"
fi
[ -n "$APP" ] && [ -d "$APP" ] || echec "app introuvable — compiler ONTMac, ou passer un chemin"

XCODE=$(xcodebuild -version)
echo "${gris}→ ${XCODE%%$'\n'*}  ·  $(basename "$APP")  ·  fenêtre $TAILLE${fin}"

pkill -f "La Bible ONT" 2>/dev/null || true
sleep 2
rm -rf "$SORTIE" && mkdir -p "$SORTIE"

open -a "$APP" --args -tailleDeCapture "$TAILLE"
LIGNE=$(attendre_la_fenetre) || echec "la fenêtre n'atteint pas $TAILLE — Stage Manager l'a peut-être garée"

# **L'écran de lancement doit avoir fini.** La fenêtre atteint sa taille avant
# que la montagne du démarrage ne s'efface : le premier jet a capturé le splash
# en croyant capturer le corpus. La fenêtre était de la bonne taille, et l'image
# ne montrait pas l'app.
echo "${gris}  l'écran de lancement s'efface…${fin}"
sleep 6

i=0
for cible in "${ECRANS[@]}"; do
  i=$((i + 1))
  if [ -n "$cible" ]; then
    open -a "$APP" "$cible"
  else
    open -a "$APP"
  fi
  LIGNE=$(attendre_la_fenetre) || echec "fenêtre perdue avant la capture $i"
  ID=$(printf '%s' "$LIGNE" | cut -f1)
  # Une seconde de plus : la navigation est animée, et une capture prise au
  # milieu montre deux écrans superposés.
  sleep 2

  F="$SORTIE/$(printf '%02d' $i).png"
  screencapture -o -x -l "$ID" "$F" || echec "capture $i impossible"

  L=$(sips -g pixelWidth "$F" | tail -1 | awk '{print $2}')
  H=$(sips -g pixelHeight "$F" | tail -1 | awk '{print $2}')
  if [ "$L" != "$ATTENDU_L" ] || [ "$H" != "$ATTENDU_H" ]; then
    rm -f "$F"
    echec "capture $i rendue en ${L}×${H}, attendu ${ATTENDU_L}×${ATTENDU_H} — rien n'est gardé"
  fi
  printf '  %s  %s×%s  %s\n' "$(basename "$F")" "$L" "$H" "${cible:-le corpus}"
done

pkill -f "La Bible ONT" 2>/dev/null || true

printf '%s✓%s %s captures dans %s\n' "$vert" "$fin" "$i" "$SORTIE"
cat <<TEXTE

${gris}  Les regarder avant de les téléverser : la taille est vérifiée, le contenu
  non. Une bannière de vault, une carte d'actions ouverte ou un verset
  sélectionné passeraient ce contrôle sans un mot.

      qlmanage -p $SORTIE/*.png

  Puis, pour les poser sur la fiche :

      cd .github/scripts && PLATEFORME=MAC_OS python3 fiche.py --captures${fin}
TEXTE
