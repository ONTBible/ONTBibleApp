#!/usr/bin/env bash
#
# Construit, signe, notarise et empaquette la liseuse du Mac pour Homebrew.
#
#   ./scripts/publier-le-cask.sh 1.0.5
#
# ## Ce que ce chemin est, et n'est pas
#
# C'est la distribution **hors App Store** : un zip notarisé, téléchargé par
# `brew install --cask ontbible/ont/la-bible-ont`. Il ne remplace pas la chaîne
# TestFlight/App Store — il s'y ajoute, sans consommer une place du quota
# Apple : la notarisation n'est pas un téléversement App Store Connect.
#
# ## Ce qu'il exige
#
# - une identité « Developer ID Application » dans le trousseau — PAS
#   « Apple Development » ni « Apple Distribution », qui ne valent que pour
#   l'App Store. Elle se crée dans Xcode → Réglages → Comptes → Gérer les
#   certificats, par le titulaire du compte ;
# - la clé App Store Connect pour `notarytool` : `ASC_KEY_ID` et
#   `ASC_ISSUER_ID` dans l'environnement, le .p8 dans ~/private_keys/ ;
# - le corpus : `ONT_VAULT` ou un `dist/` déjà construit (scripts/corpus.sh).
#
# ## Pourquoi des droits réduits
#
# Voir `app/ONTMac-cask.entitlements` : les droits restreints (connexion
# Apple, push, liens universels) exigent un profil Developer ID qu'on
# n'embarque pas — présents sans profil, macOS refuse de lancer l'app.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
echec() { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; exit 1; }

VERSION="${1:?version attendue — ex. 1.0.5}"
: "${ASC_KEY_ID:?ASC_KEY_ID manquant}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID manquant}"

IDENTITE=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$IDENTITE" ] || echec "aucune identité « Developer ID Application » dans le trousseau — voir l'en-tête"
echo "${gris}→ signature : $IDENTITE${fin}"

DD="${TMPDIR:-/tmp}/dd-ont-cask"
echo "→ le projet"
(cd app && xcodegen generate >/dev/null)

echo "→ la compilation (Release)"
xcodebuild build -project app/ONT.xcodeproj -scheme ONTMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
  > "${TMPDIR:-/tmp}/ont-cask-build.log" 2>&1 \
  || echec "compilation — voir ${TMPDIR:-/tmp}/ont-cask-build.log"

APP=$(find "$DD/Build/Products/Release" -maxdepth 1 -name "*.app" -print -quit)
[ -n "$APP" ] || echec "aucune app produite"

# **Pas de pipeline embarqué** : la version Homebrew est celle d'un lecteur,
# comme le canal bêta — le mode vault est un outil d'auteur.

echo "→ la signature Developer ID, exécution durcie"
codesign --force --options runtime --timestamp \
  --entitlements app/ONTMac-cask.entitlements \
  --sign "$IDENTITE" "$APP" || echec "codesign"
codesign --verify --strict "$APP" || echec "la signature ne se vérifie pas"

echo "→ la notarisation"
ZIP_NOTAIRE=$(mktemp -d)/notaire.zip
ditto -c -k --keepParent "$APP" "$ZIP_NOTAIRE"
xcrun notarytool submit "$ZIP_NOTAIRE" \
  --key ~/private_keys/AuthKey_"$ASC_KEY_ID".p8 \
  --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait || echec "notarytool a refusé — voir son journal (notarytool log)"
xcrun stapler staple "$APP" || echec "stapler"

SORTIE="La-Bible-ONT-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$SORTIE"
SHA=$(shasum -a 256 "$SORTIE" | cut -d' ' -f1)
printf '%s✓%s %s\n' "$vert" "$fin" "$SORTIE"
echo "sha256: $SHA"
