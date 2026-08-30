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
# **L'estampille du corpus vient d'ici, pas du pipeline.**
#
# La date du dernier commit du vault — celle de son *contenu*, et non de sa
# compilation. C'est elle qui permet à une liseuse de savoir si le corpus publié
# est plus récent que celui qu'elle embarque ; une empreinte dit que deux corpus
# diffèrent, jamais lequel vient après.
#
# Le pipeline ne lit pas `.git` lui-même : il resterait dépendant de la forme du
# checkout — un export d'archive, un `--depth 1`, un vault copié sans `.git`, et
# il tomberait. Il reste une fonction pure de ses entrées.
#
# Vide si le vault n'est pas un dépôt git. Les liseuses refusent alors le
# manifeste publié, ce qui gèle la mise à jour au lieu de risquer un corpus
# remplacé par du plus ancien. Un texte figé se voit ; un texte silencieusement
# rajeuni à l'envers ne se voit pas.
VAULT="${ONT_VAULT:-$(cd "$(dirname "$0")/../../ONTBibleTranslation" && pwd)}"
ONT_GENERE="$(git -C "$VAULT" log -1 --format=%cI 2>/dev/null || true)"
export ONT_GENERE
if [ -n "$ONT_GENERE" ]; then
  echo "→ le corpus — vault du $ONT_GENERE"
else
  echo "→ le corpus — sans estampille : la mise à jour à distance restera gelée"
fi
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
