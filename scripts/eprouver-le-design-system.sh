#!/usr/bin/env bash
#
# Le design system est-il employé, ou contourné ?
#
#   ./scripts/eprouver-le-design-system.sh
#
# ## Pourquoi ce contrôle existe
#
# Le 13 septembre 2026, l'auteur a relevé sur deux captures que l'onglet des
# chuqqot ne ressemblait pas aux cinq autres : titre petit et centré au lieu du
# grand titre, puis contenu collé au bord de l'iPad au lieu d'être borné.
#
# **Deux divergences, le même onglet, la même heure.** Les deux compilaient. Les
# deux passaient toutes les épreuves. Aucune n'était visible autrement qu'en
# mettant deux onglets côte à côte — ce qu'aucun écran de test ne fait.
#
# > **Une convention qui tient par la recopie ne tient pas.**
#
# Ce script mesure ce qu'un compilateur ne peut pas : qu'une règle de forme est
# suivie partout, et pas seulement là où quelqu'un a pensé à la recopier.
#
# ## Ce qu'il ne fait pas
#
# Il ne juge pas le goût. Un écart délibéré se marque avec un commentaire qui
# le dit, et se lit alors comme une décision — c'est ce que le dépôt demande
# partout ailleurs.
#
# ## Les cliquets
#
# Les plafonds descendent, jamais ils ne montent. Un cliquet qu'on desserre
# sans le nommer ne cliquette plus : le relever se dit dans le commit.
set -euo pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES="$RACINE/app/Packages/ONTFeatures/Sources"
DS="$RACINE/app/Packages/ONTDesignSystem/Sources/ONTDesignSystem"

vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
defauts=0
sections=0

titre() { sections=$((sections + 1)); printf '\n%s\n' "$1"; }
ok()    { printf '  %s✓%s %s\n' "$vert" "$fin" "$1"; }
ko()    { printf '  %s✗%s %s\n' "$rouge" "$fin" "$1"; defauts=$((defauts + 1)); }
note()  { printf '    %s%s%s\n' "$gris" "$1" "$fin"; }

titre "Les racines d'onglet"

# **Chaque onglet est une racine, et une racine est une chose.**
#
# `ontOngletRacine` pose le fond et le grand titre ; `ontColumn` borne la
# largeur sur iPad. Les deux ne s'appliquent pas au même niveau — l'un dans la
# pile de navigation, l'autre autour — donc ils restent deux appels, et c'est
# précisément ce qui permet d'en oublier un.
#
# `BookTab` n'est pas une racine : c'est une destination poussée depuis Bible.
for f in "$SOURCES"/*/Presentation/*Tab.swift; do
    nom="$(basename "$f" .swift)"
    [ "$nom" = "BookTab" ] && continue

    # **L'appel, pas le mot.** La première version cherchait la chaîne
    # n'importe où, et la trouvait dans les commentaires qui la citent — dont
    # celui qui explique pourquoi elle est là. Retirée du code, elle restait
    # donc « présente », et le contrôle annonçait vert sur le défaut même
    # qu'il venait d'être écrit pour attraper.
    #
    # Trouvé en retirant `ontColumn` de Chuqqot pour voir si le contrôle
    # rougissait. Il n'a pas rougi. Un contrôle qui ne sait pas échouer ne
    # mesure rien.
    manque=""
    grep -qE "^\s*\.ontOngletRacine\(" "$f" || manque="$manque ontOngletRacine"
    grep -qE "^\s*\.ontColumn\(" "$f" || manque="$manque ontColumn"

    if [ -n "$manque" ]; then
        ko "$nom manque :$manque"
        note "une racine d'onglet pose les deux — voir ONTPlateformes.swift"
    else
        ok "$nom"
    fi
done

titre "Le titre compact, réservé aux écrans poussés"

# `ontTitreCompact` rend le titre petit et centré. C'est la forme d'un écran
# **poussé**, qui arrive avec un bouton de retour. Sur une racine d'onglet, il
# efface le grand titre qui signale qu'on ouvre une section.
fautifs=0
for f in "$SOURCES"/*/Presentation/*Tab.swift; do
    nom="$(basename "$f" .swift)"
    # Sur la ligne qui suit immédiatement `ontOngletRacine` — les autres
    # emplois du fichier concernent les destinations poussées, et sont justes.
    if grep -A1 -E "^\s*\.ontOngletRacine\(" "$f" 2>/dev/null | grep -qE "^\s*\.ontTitreCompact\("; then
        ko "$nom pose ontTitreCompact sur sa racine"
        fautifs=$((fautifs + 1))
    fi
done
[ "$fautifs" -eq 0 ] && ok "aucune racine n'écrase son grand titre"

titre "L'échelle, plutôt que des nombres"

# **Une valeur en dur ne suit pas le facteur d'échelle du Mac.**
#
# `ONTUI.points()` est l'identité sur iOS — un `12` y vaut exactement
# `spacing.m`. Sur macOS il applique le facteur, et les deux divergent. Le
# nombre écrit à la main est donc juste sur iPhone et faux sur le Mac, ce qui
# est la pire des deux façons de se tromper : celle qui ne se voit pas là où
# l'on regarde.
#
# Et même à valeur égale, `4` ne dit pas « le pas le plus fin » ; `spacing.xs`
# le dit.
PLAFOND_VALEURS_EN_DUR=0
compte="$(grep -rhoE '(\.padding\((\.[a-z]+, )?(4|8|12|16|22|24|32)\)|spacing: (4|8|12|16|22|24|32)\b)' \
    --include='*.swift' "$SOURCES" | wc -l | tr -d ' ')" || compte=0
if [ "$compte" -gt "$PLAFOND_VALEURS_EN_DUR" ]; then
    ko "$compte valeur(s) de l'échelle écrite(s) en dur, le plafond est à $PLAFOND_VALEURS_EN_DUR"
    grep -rnE '(\.padding\((\.[a-z]+, )?(4|8|12|16|22|24|32)\)|spacing: (4|8|12|16|22|24|32)\b)' \
        --include='*.swift' "$SOURCES" | sed "s|$SOURCES/||" | head -10 | while read -r l; do note "$l"; done
    note "4→xs  8→s  12→m  16→l  22→page  24→xl  32→xxl"
else
    ok "aucune valeur de l'échelle écrite en dur"
fi

titre "Les couleurs, par le thème"

# Une couleur du système ne connaît ni le parchemin, ni la nuit d'aubergine, et
# ne suit aucun des quatre thèmes. `ONTColors` les connaît tous.
PLAFOND_COULEURS_SYSTEME=0
compte="$(grep -rhoE '\bColor\.(white|black|gray|red|blue|green|orange|yellow|purple|pink)\b' \
    --include='*.swift' "$SOURCES" | wc -l | tr -d ' ')" || compte=0
if [ "$compte" -gt "$PLAFOND_COULEURS_SYSTEME" ]; then
    ko "$compte couleur(s) du système, le plafond est à $PLAFOND_COULEURS_SYSTEME"
    note "ONTColors les porte toutes, et elles suivent les quatre thèmes"
else
    ok "aucune couleur du système"
fi

titre "Le mode d'affichage du titre, par le design system"

# `navigationBarTitleDisplayMode` appelé directement contourne les deux
# modificateurs qui le posent, et rend le choix invisible à ce contrôle.
PLAFOND_TITRES_DIRECTS=0
compte="$(grep -rhoE 'navigationBarTitleDisplayMode' --include='*.swift' "$SOURCES" | wc -l | tr -d ' ')" || compte=0
if [ "$compte" -gt "$PLAFOND_TITRES_DIRECTS" ]; then
    ko "$compte appel(s) direct(s), le plafond est à $PLAFOND_TITRES_DIRECTS"
    note "ontOngletRacine pour une racine, ontTitreCompact pour un écran poussé"
else
    ok "aucun appel direct"
fi

printf '\n'
# **Le compte des sections, parce qu'un script peut s'arrêter au milieu.**
# Il l'a fait : `set -e` et un `grep` sans résultat — qui est le cas normal —
# le tuaient après trois sections, en laissant des ✓ à l'écran.
if [ "$sections" -ne 5 ]; then
    printf '%s%d section(s) sur 5 — le contrôle a été interrompu en chemin.%s\n' "$rouge" "$sections" "$fin"
    exit 1
fi
if [ "$defauts" -gt 0 ]; then
    printf '%s%d défaut(s) — le design system est contourné quelque part.%s\n' "$rouge" "$defauts" "$fin"
    exit 1
fi
printf '%sLe design system est employé partout où ce contrôle sait regarder.%s\n' "$vert" "$fin"
