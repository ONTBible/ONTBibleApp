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
# **En UTC, terminée par `Z`, et c'est une contrainte, pas un goût.** Les
# liseuses comparent ces dates comme des chaînes : deux écritures du même instant
# s'ordonnent alors à l'envers dès que le fuseau diffère.
#
#     "2026-08-30T00:14:00Z"  <  "2026-08-30T02:14:00+02:00"     → vrai
#
# L'app garderait le plus ancien des deux corpus en croyant garder le plus
# récent — le défaut d'aujourd'hui, mais sous une date bien formée, donc bien
# plus difficile à voir qu'un champ vide.
#
# `%cI` ne convient pas : il rend l'offset du commit. Et `--date=format:` garde
# l'heure **du commit** en y collant notre `Z` — une date fausse de deux heures,
# parfaitement plausible. Il faut `format-local` avec `TZ=UTC`, qui convertit.
VAULT="${ONT_VAULT:-$(cd "$(dirname "$0")/../../ONTBibleTranslation" && pwd)}"
ONT_GENERE="$(TZ=UTC git -C "$VAULT" log -1 \
  --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd 2>/dev/null || true)"

# **Le recoupement, et il n'est pas décoratif.**
#
# Ce qui précède est juste aujourd'hui. Le jour où quelqu'un retire `TZ=UTC`, ou
# revient à `--date=format:` en trouvant `format-local` obscur — ce que j'ai
# failli faire moi-même —, la commande rend l'heure **du commit** avec un `Z`
# collé dessus. Vingt signes, secondes présentes, `Z` final : la garde de forme
# du pipeline la laisse passer, celle des liseuses aussi, et la chaîne publie
# une date fausse de deux heures.
#
# On recalcule donc par un chemin qui ne connaît aucun fuseau — l'horodatage
# brut du commit — et on refuse si les deux ne concordent pas. Le défaut devient
# impossible au lieu d'être évité par un commentaire.
if [ -n "$ONT_GENERE" ]; then
  EPOCH="$(git -C "$VAULT" log -1 --format=%ct)"
  # BSD et GNU ne prennent pas le même drapeau ; on essaie les deux.
  TEMOIN="$(date -u -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
         || date -u -d "@$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  if [ -z "$TEMOIN" ]; then
    echo "✗ impossible de recouper l'estampille — ni date -r ni date -d" >&2
    exit 1
  fi
  if [ "$ONT_GENERE" != "$TEMOIN" ]; then
    echo "✗ l'estampille ne concorde pas avec l'horodatage du commit :" >&2
    echo "    calculée : $ONT_GENERE" >&2
    echo "    attendue : $TEMOIN" >&2
    echo "  La date porte un « Z » sans être en UTC. Vérifier TZ et format-local." >&2
    exit 1
  fi
fi
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
