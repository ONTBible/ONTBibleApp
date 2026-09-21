#!/usr/bin/env bash
#
# Les captures de la fiche montrent-elles encore l'app ?
#
#     ./scripts/eprouver-la-fraicheur-des-captures.sh
#
# ## Le défaut, qui a récidivé trois fois
#
# Les affiches de l'App Store sont des PNG **commités**, et rien ne les relie à
# l'interface qu'elles montrent. Elles ne se cassent donc jamais : elles
# vieillissent. Une capture périmée a la bonne taille, passe tous les contrôles
# existants, et montre une app qui n'existe plus.
#
#     13 août 2026   survivent à deux refontes de la mise en page iPad
#                    — le LISEZ-MOI du dossier le raconte déjà
#     19 août 2026   les affiches iPhone et iPad y restent un mois, et la
#                    vitrine publique de la 1.0.6 montre quatre onglets
#                    pour une app qui en a cinq
#     31 août 2026   celles du Mac traversent la refonte entière
#
# La garde de `soumettre.py` refuse une version **sans** captures. Personne ne
# refusait une version aux captures **fausses**.
#
# ## Pourquoi grossier, et pourquoi c'est un choix
#
# La forme fine — un manifeste où chaque capture déclare la scène qu'elle
# montre et le commit d'où elle sort — serait silencieuse et précise. Elle
# serait aussi **une déclaration**, donc falsifiable : un chemin mal listé, une
# scène renommée, et la garde reste verte en regardant le mauvais dossier.
# C'est exactement la classe de défaut qu'on passe ses journées à retirer.
#
# Celle-ci ne déclare rien. Elle compare deux dates que git tient de lui-même,
# et il n'y a rien à falsifier. Le prix est le bruit : **toute** modification
# de l'interface rend **tous** les jeux suspects, même ceux qu'elle ne touche
# pas. Un contrôle bruyant qu'on affine vaut mieux qu'un contrôle fin qui ment,
# parce que le bruit se remarque et le mensonge non. L'argument est de la
# session Android, le 18 septembre 2026.
#
# ## Ce qu'il n'attrape pas, et il faut le dire
#
# **Les scènes cassées par la donnée.** La quatrième capture du Mac visait
# `ont://term/elohim` ; le demi-anneau est devenu signifiant le 16 septembre,
# la clé du glossaire est devenue `ʾelohim`, et la vitrine a montré « Terme non
# documenté » — sans qu'une seule ligne d'interface ait bougé. Ce contrôle-là
# serait resté vert.
#
# Il ne mesure donc qu'une chose, et c'est écrit pour qu'on ne lui en prête pas
# plus : **l'interface a-t-elle changé depuis que ces images ont été prises.**
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'
rouge=$'\033[31m'
gris=$'\033[90m'
fin=$'\033[0m'

# Ce qui dessine. **Pas `app/Resources/data`** : le corpus est republié plus
# souvent que l'app ne change d'allure, et l'inclure rendrait ce contrôle rouge
# en permanence — c'est-à-dire éteint.
INTERFACE=(
    "app/Sources"
    "app/MacSources"
    "app/Packages/ONTFeatures"
    "app/Packages/ONTDesignSystem"
    "app/Packages/ONTKit"
)

# Les jeux commités, ceux qu'on téléverse. `brut/` est régénérable et ignoré.
JEUX=(
    "app/Captures/mac"
    "app/Captures/iphone-6.9"
    "app/Captures/ipad-13"
)

horodate() { git log -1 --format=%ct -- "$@" 2>/dev/null; }
en_clair() { git log -1 --format='%cs %h' -- "$@" 2>/dev/null; }

DERNIERE_INTERFACE=0
for chemin in "${INTERFACE[@]}"; do
    quand=$(horodate "$chemin")
    [ -n "$quand" ] && [ "$quand" -gt "$DERNIERE_INTERFACE" ] && DERNIERE_INTERFACE=$quand
done

if [ "$DERNIERE_INTERFACE" -eq 0 ]; then
    # **Ne rien trouver n'est pas trouver zéro.** Sans date d'interface, ce
    # contrôle ne peut rien comparer : le dire vaut mieux que passer au vert.
    printf '%s✗%s aucun commit trouvé sur les chemins d'"'"'interface — ce contrôle ne mesure rien ici\n' \
        "$rouge" "$fin" >&2
    exit 1
fi

printf '%sinterface, dernier mouvement : %s%s\n' "$gris" \
    "$(git log -1 --format='%cs %h' -- "${INTERFACE[@]}")" "$fin"

perimes=0
for jeu in "${JEUX[@]}"; do
    [ -d "$jeu" ] || continue
    quand=$(horodate "$jeu")
    if [ -z "$quand" ]; then
        printf '%s✗%s %-24s jamais commité\n' "$rouge" "$fin" "$jeu"
        perimes=$((perimes + 1))
        continue
    fi
    if [ "$quand" -lt "$DERNIERE_INTERFACE" ]; then
        jours=$(((DERNIERE_INTERFACE - quand) / 86400))
        printf '%s✗%s %-24s %s — %s jours avant le dernier changement d'"'"'interface\n' \
            "$rouge" "$fin" "$jeu" "$(en_clair "$jeu")" "$jours"
        perimes=$((perimes + 1))
    else
        printf '%s✓%s %-24s %s\n' "$vert" "$fin" "$jeu" "$(en_clair "$jeu")"
    fi
done

if [ "$perimes" -gt 0 ]; then
    cat >&2 <<TEXTE

${rouge}✗${fin} $perimes jeu(x) pris avant le dernier changement d'interface.

  Ça ne prouve pas qu'ils sont faux — l'interface a pu changer ailleurs que
  dans ce qu'ils montrent. Ça prouve que ${rouge}personne ne peut affirmer
  qu'ils sont justes${fin}, et c'est tout ce qu'un contrôle grossier doit dire.

  Les refaire :

      ./scripts/captures-mac.sh          le Mac
      ./scripts/captures.sh              l'iPhone et l'iPad

  Puis les regarder — la taille est vérifiée, le contenu non.
TEXTE
    exit 1
fi

printf '%s✓%s les jeux commités sont postérieurs au dernier changement d'"'"'interface\n' \
    "$vert" "$fin"
