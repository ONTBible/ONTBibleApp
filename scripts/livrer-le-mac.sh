#!/usr/bin/env bash
#
# Livre la liseuse macOS à App Store Connect, depuis cette machine.
#
#   ./scripts/livrer-le-mac.sh              # le canal vient de la branche
#   ./scripts/livrer-le-mac.sh interne      # ou on le force
#   ./scripts/livrer-le-mac.sh interne --a-blanc   # tout, sauf archiver et livrer
#
# ## Pourquoi ce script existe, et qui l'appelle
#
# `livraison.yml` livre l'iPhone depuis un runner GitHub. Le Mac ne peut pas y
# aller : l'`actool` d'Xcode 26.3 — la seule version que l'image propose, alors
# que le workflow demande déjà `latest` — **plante** en composant le bundle
# Icon Composer pour macOS. Pas une erreur de validation : un plantage, sans un
# mot sur ce qu'il reproche. Mesuré en réactivant l'icône dans le job.
#
# D'où ce script : la même chaîne, sur une machine dont l'Xcode compose l'icône.
# Il a **deux appelants**, et c'est délibéré — le même fichier des deux côtés,
# pour qu'une correction ne s'applique jamais à un seul :
#
#   - à la main, sur cette machine, quand on veut livrer sans passer par la CI ;
#   - le job `mac` de `livraison.yml`, sur le runner **auto-hébergé** de cette
#     même machine.
#
# Le runner auto-hébergé demande une précaution que `ONTBibleApp` étant public
# rend obligatoire : une proposition venue d'un fork ne doit **jamais** pouvoir
# s'exécuter ici. C'est réglé côté dépôt — l'approbation est exigée pour tout
# contributeur externe (`approval_policy: all_external_contributors`), et non
# par ce fichier. Le vérifier avant de toucher aux réglages Actions.
#
# Le jour où l'image du runner GitHub monte de version, le job repasse chez eux
# et le runner s'éteint ; ce script, lui, reste bon pour la livraison à la main.
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
# ── À blanc : le seul moyen d'éprouver ce script sans livrer
#
# Trois défauts s'y sont succédé le 31 août 2026, découverts **un par un**, à
# vingt minutes de CI et une tentative de livraison chacun : un tuyau qui tuait
# `xcodebuild`, une variable collée à un caractère multi-octets, et avant eux la
# plateforme absente d'une requête. Aucun n'était visible à la lecture ; tous
# l'étaient à l'exécution.
#
# `--a-blanc` fait tout ce qui est vérifiable — les gardes, la version d'Xcode,
# la composition de l'icône, le numéro de build, la mutation du plist et sa
# restauration — et **s'arrête avant d'archiver**. Ce qu'il ne couvre pas est
# dit à la fin plutôt que sous-entendu.
A_BLANC=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --a-blanc) A_BLANC=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

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
#
# À blanc, ces trois-là ne sont pas exigées : on ne parle à personne. Les exiger
# quand même rendrait la vérification impossible sur une machine qui n'a pas la
# clé — c'est-à-dire précisément là où on voudrait la lancer avant de pousser.
if [ "$A_BLANC" -eq 0 ]; then
  [ -n "${ASC_KEY_ID:-}" ] || echec "exporter ASC_KEY_ID — identifiant de la clé App Store Connect"
  [ -n "${ASC_ISSUER_ID:-}" ] || echec "exporter ASC_ISSUER_ID — identifiant de emetteur"
  CLE="$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [ -f "$CLE" ] || echec "clé absente : $CLE"
else
  CLE="(aucune — à blanc)"
fi

# **Sans tuyau, et ce n'est pas une coquetterie.**
#
# `xcodebuild -version | head -1` a fait échouer la toute première livraison du
# Mac, en 0,26 seconde et avec le code 134. `head` lit sa ligne et ferme le
# tuyau ; `xcodebuild` écrit alors la seconde — « Build version … » — dans un
# descripteur fermé.
#
# Un programme ordinaire meurt là sur `SIGPIPE`, ce qui rend 141. Celui d'Xcode
# 27 lève une `NSFileHandleOperationException` que personne ne rattrape, et
# avorte : `SIGABRT`, donc 134. C'est ce chiffre qui m'a fait écarter la piste
# du tuyau pendant une demi-heure — je cherchais 141.
#
# La course est de surcroît gagnée la plupart du temps en interactif, où tout
# tient dans une seule écriture : le défaut ne se voit qu'en CI.
XCODE=$(xcodebuild -version)
XCODE=${XCODE%%$'\n'*}
# `${gris}` accolé, et non `$gris` : bash lit `$gris→` comme **un seul nom de
# variable** — il ne s'arrête pas au premier octet du caractère multi-octets.
# Sous `set -u`, ce nom introuvable arrête le script, et le message accuse une
# variable qui n'existe pas plutôt que la ligne qui l'a inventée.
#
# Cette ligne était fautive depuis le premier jour. Personne ne l'avait vu :
# le script mourait deux lignes plus haut, sur le tuyau d'`xcodebuild`.
echo "${gris}→ $XCODE  ·  branche $BRANCHE  ·  canal $CANAL${GROUPE:+ (groupe « $GROUPE »)}$fin"

# **On ne devine pas si l'icône passera : on le mesure d'abord.**
#
# `actool` plante sans diagnostic sur les versions qui ne savent pas composer le
# bundle pour macOS. Le découvrir au milieu d'une archive de plusieurs minutes
# coûte l'archive ; le découvrir ici coûte quelques secondes. Et un `grep` sur
# le numéro de version serait un pari : on demande à l'outil lui-même.
# **La signature, d'abord — une seconde plutôt que cinq minutes.**
#
# Le 31 août 2026, la première livraison qui a compilé pour de bon a échoué au
# bout d'une minute sur `errSecInternalComponent` : `codesign` n'obtenait pas la
# clé privée. Ni certificat manquant ni trousseau verrouillé — la **liste de
# partition** de la clé n'autorisait pas un appelant non interactif, et sous
# `launchd` personne ne peut cliquer « Autoriser ».
#
# Le même geste réussit depuis un shell de la session, ce qui rend le défaut
# invisible à qui essaie à la main. On le sonde donc explicitement, sur un
# binaire jetable, avant de dépenser une archive.
echo "→ la signature, avant tout le reste"
SONDE=$(mktemp -d)/sonde
cp /bin/ls "$SONDE"
IDENTITE_ESSAI=$(security find-identity -v -p codesigning 2>/dev/null \
                 | grep "Apple Distribution" | head -1 | awk '{print $2}')
if [ -z "$IDENTITE_ESSAI" ]; then
  echec "aucune identité « Apple Distribution » dans le trousseau"
fi
if ! codesign --force --sign "$IDENTITE_ESSAI" "$SONDE" > /tmp/ont-signature.log 2>&1; then
  if grep -q "errSecInternalComponent" /tmp/ont-signature.log; then
    printf '%s✗%s codesign n'"'"'obtient pas la clé privée — errSecInternalComponent\n' "$rouge" "$fin" >&2
    cat >&2 <<AIDE
${gris}  Le certificat est là et le trousseau est ouvert : c'est la liste de
  partition de la clé qui refuse un appelant non interactif. Une fois pour
  toutes, dans une session interactive :

      security set-key-partition-list -S apple-tool:,apple:,codesign: \\
              -s ~/Library/Keychains/login.keychain-db

  Le geste réussit sans ça depuis un Terminal, et échoue sous launchd — c'est
  ce qui le rend si facile à ne pas voir.${fin}
AIDE
    exit 1
  fi
  echec "codesign refuse — voir /tmp/ont-signature.log"
fi
rm -rf "$(dirname "$SONDE")"

# **L'icône, et rien d'autre.**
#
# Sans signature : ce qu'on veut savoir ici est si `actool` compose le bundle
# Icon Composer pour macOS, et la signature n'y entre pour rien. La mêler
# faisait échouer cette étape pour une raison qu'elle nommait mal.
echo "→ l'icône"
if ! xcodebuild build \
      -project app/ONT.xcodeproj -scheme ONTMac -destination 'platform=macOS' \
      CODE_SIGNING_ALLOWED=NO > /tmp/ont-icone.log 2>&1; then
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

# Sous Actions, le numéro remonte au job : c'est lui qui rattachera le build au
# groupe TestFlight, et il ne peut pas le deviner — deux `date` séparés d'une
# minute ne rendent pas le même.
#
# Écrit en `if` plutôt qu'en `[ … ] && …`. Mesuré, et contre mon attente :
# `set -e` **laisse passer** une liste `&&` dont le test échoue au milieu d'un
# script. Mais la liste rend tout de même non-zéro, et le jour où cette ligne se
# retrouve en dernière position d'une fonction ou du fichier, c'est le script
# entier qui rendra non-zéro. La forme longue n'a pas ce bord.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "build=$BUILD" >> "$GITHUB_OUTPUT"
fi

if [ "$A_BLANC" -eq 1 ]; then
  printf '%s✓%s à blanc — tout ce qui précède l'"'"'archive a été exécuté\n' "$vert" "$fin"
  cat <<TEXTE
${gris}  Vérifié : les gardes, ${XCODE}, la composition de ONT.icon, le numéro
  ${BUILD}, la mutation de Info-Mac.plist et sa restauration par le trap.

  **Non vérifié** : l'archive, l'export, le téléversement, et tout ce que le
  compte App Store Connect refuse ou accepte. Un « à blanc » vert ne dit rien
  de la livraison — il dit seulement que le script ne se casse plus tout seul.${fin}
TEXTE
  exit 0
fi

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
