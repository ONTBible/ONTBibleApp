#!/usr/bin/env bash
#
# Le vault devient des données, puis un projet Xcode.
#
#   ./scripts/corpus.sh
#
# Trois gestes qui vont toujours ensemble, et qu'on ne veut pas voir se
# désynchroniser :
#
#   1. le pipeline lit le vault et écrit `dist/`
#   2. le schéma engendre les DTO Swift
#   3. `dist/` est recopié dans les ressources de l'app
#   4. `xcodegen` engendre le projet, qui n'est pas committé
#
# C'était `npm run app`. Le pipeline est en Rust depuis le 14 août 2026 : un
# binaire, sans runtime à installer — ni sur cette machine, ni dans les deux CI
# qui le rejouent.

set -euo pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RACINE"

vert=$'\033[32m'; fin=$'\033[0m'

# `--release` et non le profil de développement.
#
# Le pipeline parcourt le corpus entier avec des expressions rationnelles
# Unicode ; en débogage il met une trentaine de secondes là où il en met deux.
# La compilation du binaire est mise en cache par cargo, donc on ne la paie
# qu'une fois.
echo "→ le corpus"
cargo run --manifest-path pipeline/Cargo.toml --bin ont-pipeline --release --quiet

# Les DTO Swift, engendrés depuis `schema.rs`.
#
# **Inconditionnel, et c'est le point.** Aucun déclencheur à écrire, donc aucun
# filtre de chemins à oublier de mettre à jour : le fichier est réécrit à chaque
# fois, il ne peut pas être périmé. C'est la même règle que `ONT.xcodeproj`, et
# pour la même raison — committer les deux, c'est garantir qu'ils divergeront.
echo "→ le schéma Swift"
cargo run --manifest-path pipeline/Cargo.toml --bin engendrer --release --quiet

echo "→ les ressources de l'app"
# `rm -rf` d'abord : une copie par-dessus laisserait en place un livre retiré
# du vault, que l'app continuerait d'afficher sans que rien ne l'explique.
rm -rf app/Resources/data
mkdir -p app/Resources/data
cp dist/*.json app/Resources/data/
cp -R dist/books app/Resources/data/

echo "→ le projet Xcode"
(cd app && xcodegen generate)

printf '%s✓%s corpus, ressources et projet à jour\n' "$vert" "$fin"
