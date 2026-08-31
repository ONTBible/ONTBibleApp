#!/usr/bin/env bash
#
# Livre la liseuse macOS à App Store Connect, depuis cette machine.
#
#   ./scripts/livrer-le-mac.sh              # le canal vient de la branche
#   ./scripts/livrer-le-mac.sh interne      # ou on le force
#
# ## Pourquoi ce geste n'est pas un workflow
#
# `livraison.yml` livre l'iPhone depuis un runner GitHub. Le Mac ne peut pas y
# aller : l'`actool` d'Xcode 26.3 — la seule version que l'image propose, alors
# que le workflow demande déjà `latest` — **plante** en composant le bundle
# Icon Composer pour macOS. Pas une erreur de validation : un plantage, sans un
# mot sur ce qu'il reproche. Mesuré en réactivant l'icône dans le job.
#
# Un runner auto-hébergé réglerait la version et ouvrirait pire : `ONTBibleApp`
# est **public**, et un runner auto-hébergé sur un dépôt public laisse toute
# proposition venue d'un fork exécuter du code sur la machine. GitHub le
# déconseille explicitement, et c'est la machine de l'auteur.
#
# Reste ce que fait ce script : la même chaîne, sur la machine qui a l'Xcode
# qu'il faut, sans démon qui écoute. Le jour où l'image du runner monte de
# version, ce fichier devient un job et l'on jette celui-ci.
#
# ## Ce qu'il faut avant
#
#   - Xcode dont l'`actool` compose `ONT.icon` pour macOS — 27 le fait, 26.3 non ;
#   - la clé App Store Connect en `~/private_keys/AuthKey_<ID>.p8`, et les deux
#     identifiants en variables d'environnement — voir plus bas.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
echec() { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; exit 1; }

# ── Le canal, et il nomme un destinataire
#
# La règle est celle de `livraison.yml`, et elle ne se réinvente pas ici : une
# branche nomme **qui verra le build**, pas une manœuvre. La dupliquer serait
# accepter qu'elles divergent le jour où l'une des deux change.
BRANCHE=$(git rev-parse --abbrev-ref HEAD)
CANAL="${1:-}"
if [ -z "$CANAL" ]; then
  case "$BRANCHE" in
    main)    CANAL=appstore ;;
    staging) CANAL=beta ;;
    dev)     CANAL=interne ;;
    *) echec "branche « $BRANCHE » : préciser le canal — interne, beta ou appstore" ;;
  esac
fi
case "$CANAL" in
  appstore) GROUPE= ;;
  beta)     GROUPE=Beta ;;
  interne)  GROUPE=Dev ;;
  *) echec "canal inconnu : « $CANAL »" ;;
esac

# ── Ce qui doit être là avant qu'on touche à quoi que ce soit
#
# Vérifiés à la main plutôt que par `${VAR:?message}` : une apostrophe dans le
# message de cette forme rouvre un contexte de citation, et le script ne se
# lisait plus — « unexpected EOF while looking for matching " ». Le raccourci
# coûtait un défaut de syntaxe pour deux lignes gagnées.
[ -n "${ASC_KEY_ID:-}" ] || echec "exporter ASC_KEY_ID — identifiant de la clé App Store Connect"
[ -n "${ASC_ISSUER_ID:-}" ] || echec "exporter ASC_ISSUER_ID — identifiant de emetteur"
CLE="$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$CLE" ] || echec "clé absente : $CLE"

XCODE=$(xcodebuild -version | head -1)
echo "$gris→ $XCODE  ·  branche $BRANCHE  ·  canal $CANAL${GROUPE:+ (groupe « $GROUPE »)}$fin"

# **On ne devine pas si l'icône passera : on le mesure d'abord.**
#
# `actool` plante sans diagnostic sur les versions qui ne savent pas composer le
# bundle pour macOS. Le découvrir au milieu d'une archive de plusieurs minutes
# coûte l'archive ; le découvrir ici coûte quelques secondes. Et un `grep` sur
# le numéro de version serait un pari : on demande à l'outil lui-même.
echo "→ l'icône, avant tout le reste"
if ! xcodebuild build \
      -project app/ONT.xcodeproj -scheme ONTMac -destination 'platform=macOS' \
      -allowProvisioningUpdates > /tmp/ont-icone.log 2>&1; then
  if grep -q "CompileAssetCatalogVariant" /tmp/ont-icone.log; then
    echec "cet Xcode ne compose pas ONT.icon pour macOS — voir /tmp/ont-icone.log"
  fi
  echec "la compilation échoue — voir /tmp/ont-icone.log"
fi

# ── Le numéro de build
#
# Daté plutôt que compté, comme sur iOS : rien à conserver d'une exécution à
# l'autre, et l'ordre est garanti par le temps. Le plist du Mac est **suivi par
# git** — on le restaure quoi qu'il arrive, sans quoi ce geste laisserait un
# arbre sale derrière lui.
BUILD="$(date -u +%y%m%d).$(date -u +%H%M)"
trap 'git checkout -- app/Info-Mac.plist 2>/dev/null || true' EXIT
plutil -replace CFBundleVersion -string "$BUILD" app/Info-Mac.plist
echo "→ build $BUILD"

ARCHIVE=$(mktemp -d)/ONTMac.xcarchive

echo "→ l'archive"
xcodebuild archive \
  -project app/ONT.xcodeproj \
  -scheme ONTMac \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$CLE" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

# Les symboles sont gardés à côté de l'archive, pour la même raison qu'en CI :
# un build livré sans eux est illisible pour toujours. `uploadSymbols` les
# envoie aussi à Apple, mais ce qu'Apple garde n'est pas ce qu'on relit.
SYMBOLES="$HOME/Library/Developer/Xcode/Archives/ONTMac-dSYMs/$BUILD"
mkdir -p "$SYMBOLES" && cp -R "$ARCHIVE/dSYMs/." "$SYMBOLES/" 2>/dev/null || true
echo "$gris  symboles gardés dans $SYMBOLES$fin"

echo "→ l'export et l'envoi"
EXPORT=$(mktemp -d)/export.plist
cat > "$EXPORT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <!-- `destination: upload` téléverse depuis `exportArchive`, sans passer par
       `altool` — déprécié — ni par fastlane, qui ajouterait Ruby pour faire la
       même chose. C'est le choix qu'a déjà fait la livraison iOS. -->
  <key>destination</key><string>upload</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$CLE" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

printf '%s✓%s build %s envoyé — canal %s\n' "$vert" "$fin" "$BUILD" "$CANAL"
cat <<TEXTE

$gris  Apple traite le build après réception — vérification, indexation des
  symboles. Cinq à trente minutes, et il n'est pas distribuable avant.

  Le rattachement au groupe et la demande de revue passent par les mêmes
  scripts que l'iPhone :

      cd .github/scripts && python3 beta.py        # groupe ${GROUPE:-—}
      cd .github/scripts && python3 soumettre.py   # si canal appstore
$fin
TEXTE
