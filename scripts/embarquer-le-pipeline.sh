#!/usr/bin/env bash
#
# Dépose `ont-pipeline` dans la liseuse du Mac, pour son mode développeur.
#
#   ./scripts/embarquer-le-pipeline.sh
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

CIBLE="$(ls -dt ~/Library/Developer/Xcode/DerivedData/ONT-*/Build/Products/Debug/*.app 2>/dev/null | head -1)"
if [ -z "$CIBLE" ]; then
  echo "✗ ONTMac.app introuvable — compiler la cible ONTMac d'abord" >&2
  exit 1
fi

# `MacOS/` et non `Resources/` : c'est là que `forAuxiliaryExecutable` cherche,
# et c'est le seul emplacement où un exécutable garde son droit d'exécution
# après signature.
install -m 755 pipeline/target/release/ont-pipeline "$CIBLE/Contents/MacOS/ont-pipeline"
echo "→ déposé dans $(basename "$CIBLE")/Contents/MacOS/"

# Sans re-signature, le système refuse de lancer un binaire ajouté après coup.
codesign --force --sign - "$CIBLE/Contents/MacOS/ont-pipeline" 2>/dev/null || true
codesign --force --sign - "$CIBLE" 2>/dev/null || true
echo "✓ prêt — « Fichier → Suivre un vault… » dans l'app"
