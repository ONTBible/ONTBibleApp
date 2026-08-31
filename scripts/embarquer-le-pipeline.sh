#!/usr/bin/env bash
#
# Dépose `ont-pipeline` dans la liseuse du Mac, pour son mode développeur.
#
#   ./scripts/embarquer-le-pipeline.sh                    # la dernière app Debug
#   ./scripts/embarquer-le-pipeline.sh chemin/vers/App.app # une app précise
#
# ## Pourquoi il est embarqué et non installé
#
# Le mode vault relance le pipeline à chaque pause dans l'écriture. Lui demander
# un binaire posé dans `/usr/local/bin` reviendrait à exiger une installation
# séparée, qui vieillirait à part : on lirait alors ses brouillons avec un
# pipeline d'il y a trois semaines, sans que rien ne le dise.
#
# Embarqué dans l'app, il est **du même âge qu'elle**.
#
# ## Pourquoi un script et non une phase de compilation
#
# Une phase ferait dépendre chaque build du Mac de `cargo`, y compris ceux qui
# ne touchent pas au pipeline. Ici on paie la construction quand on la veut.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ le pipeline, en release"
cargo build --manifest-path pipeline/Cargo.toml --bin ont-pipeline --release --quiet

# Capturé puis découpé, jamais mis en tuyau vers `head` : `ls` tué par un
# tuyau fermé rend 141, et `set -o pipefail` en fait un abandon du script.
#
# C'est le point le plus exposé du dépôt, parce que `DerivedData` **grossit à
# chaque build** : le script marche des semaines, puis cesse, et le changement
# ne vient pas de lui.
# Une cible donnée l'emporte sur la devinette. C'est par là que
# `livrer-le-mac.sh` embarque le pipeline dans l'app d'une **archive**, pour le
# seul canal interne — la devinette sur `DerivedData` n'y trouverait rien.
CIBLE="${1:-}"
if [ -z "$CIBLE" ]; then
  LISTE="$(ls -dt ~/Library/Developer/Xcode/DerivedData/ONT-*/Build/Products/Debug/*.app 2>/dev/null || true)"
  CIBLE="${LISTE%%$'\n'*}"
fi
if [ -z "$CIBLE" ] || [ ! -d "$CIBLE" ]; then
  echo "✗ app introuvable — compiler la cible ONTMac, ou passer un chemin" >&2
  exit 1
fi

# `MacOS/` et non `Resources/` : c'est là que `forAuxiliaryExecutable` cherche,
# et c'est le seul emplacement où un exécutable garde son droit d'exécution
# après signature.
install -m 755 pipeline/target/release/ont-pipeline "$CIBLE/Contents/MacOS/ont-pipeline"
echo "→ déposé dans $(basename "$CIBLE")/Contents/MacOS/"

# **Re-signer avec l'identité que l'app portait déjà, et non ad hoc.**
#
# Sans re-signature, le système refuse de lancer un binaire ajouté après coup.
# Mais une signature *ad hoc* ne se contente pas d'être plus faible : elle
# **efface les droits**. Sur une app confinée — le bac à sable est obligatoire
# à l'App Store — cela retire `app-sandbox`, `files.user-selected` et le reste,
# et le mode vault cesse de pouvoir lire quoi que ce soit.
#
# On relève donc l'identité sur l'app elle-même plutôt que de la deviner, et on
# repose les droits depuis leur source. Une app non signée — compilée avec
# `CODE_SIGNING_ALLOWED=NO` — retombe sur l'ad hoc, qui est correct là.
IDENTITE=$(codesign -dvv "$CIBLE" 2>&1 | sed -n 's/^Authority=//p' | head -1)

# **Les droits sont relevés sur l'app, et non lus dans leur source.**
#
# `ONTMac.entitlements` porte des commentaires XML. `plutil` les accepte, AMFI
# — le parseur de `codesign` — non : « syntax error ». Xcode les élague en
# engendrant son propre plist, mais celui-ci vit dans `DerivedData`, dont le
# chemin n'est pas un contrat.
#
# Ce que l'app **porte déjà** est la seule source qui soit à la fois exacte et
# stable : elle a été signée avec les droits que le profil accordait, ni plus
# ni moins.
DROITS="$(mktemp -t ont-droits).plist"
codesign -d --entitlements - --xml "$CIBLE" 2>/dev/null \
  | plutil -convert xml1 -o "$DROITS" - 2>/dev/null || true

# **Le binaire imbriqué porte ses propres droits, et il en faut deux.**
#
# Signé sans droits, il faisait rejeter la livraison entière par Apple :
#
#     App sandbox not enabled. The following executables must include the
#     "com.apple.security.app-sandbox" entitlement […] ont-pipeline
#
# Une app du Mac App Store est confinée, et **tout** exécutable qu'elle embarque
# doit l'être aussi. `inherit` dit qu'il prend le bac à sable de son parent
# plutôt que d'en ouvrir un à lui — c'est ce qui lui donne accès au dossier que
# le lecteur a désigné, et rien d'autre. Mesuré le 31 août 2026 : le fils hérite
# bien de l'autorisation du powerbox, 44 unités et 864 versets lus.
#
# Ces deux droits-là et pas ceux de l'app : recopier les siens donnerait au
# pipeline le droit au réseau et à Sign in with Apple, dont il n'a que faire.
DROITS_FILS="$(mktemp -t ont-droits-fils).plist"
cat > "$DROITS_FILS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.inherit</key><true/>
</dict>
</plist>
PLIST

if [ -n "$IDENTITE" ] && [ -s "$DROITS" ]; then
  echo "→ re-signature sous « $IDENTITE »"
  codesign --force --sign "$IDENTITE" --entitlements "$DROITS_FILS" \
    "$CIBLE/Contents/MacOS/ont-pipeline"
  codesign --force --sign "$IDENTITE" --entitlements "$DROITS" "$CIBLE"
else
  echo "→ app non signée : re-signature ad hoc"
  codesign --force --sign - --entitlements "$DROITS_FILS" \
    "$CIBLE/Contents/MacOS/ont-pipeline" 2>/dev/null || true
  codesign --force --sign - "$CIBLE" 2>/dev/null || true
fi

# **Et l'on vérifie que le fils les porte**, comme on le fait pour l'app.
# C'est la vérification qui manquait : la livraison du 31 août a été rejetée par
# Apple pour ces deux droits absents, alors que le script annonçait « 9 portés
# pour 7 demandés » — le compte de l'app, juste, et muet sur son fils.
FILS=$(codesign -d --entitlements - --xml "$CIBLE/Contents/MacOS/ont-pipeline" 2>/dev/null \
  | plutil -convert xml1 -o - - 2>/dev/null | grep -c "app-sandbox" || echo 0)
if [ "$FILS" -lt 1 ]; then
  echo "✗ ont-pipeline ne porte pas app-sandbox — Apple rejettera la livraison" >&2
  exit 1
fi
echo "→ le pipeline porte son bac à sable"

# **Et on vérifie que les droits ont survécu**, plutôt que de l'espérer.
#
# C'est le geste qui a trouvé, le 31 août, que `aps-environment` disparaissait
# en silence : la signature réussit, la liste est amputée, et rien ne relie les
# deux. Comparer ce qui est demandé à ce qui est porté coûte une ligne.
DEMANDES=$(grep -c "<key>" app/ONTMac.entitlements 2>/dev/null || echo 0)
PORTES=$(codesign -d --entitlements - --xml "$CIBLE" 2>/dev/null \
  | plutil -convert xml1 -o - - 2>/dev/null | grep -c "<key>" || echo 0)
echo "→ droits : $PORTES portés pour $DEMANDES demandés"

echo "✓ prêt — « Fichier → Suivre un vault… » dans l'app"
