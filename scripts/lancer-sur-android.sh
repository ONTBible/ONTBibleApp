#!/usr/bin/env bash
#
# Construit la liseuse Android et la lance sur l'appareil ou l'émulateur.
#
#   ./scripts/lancer-sur-android.sh              # construit, installe, lance
#   ./scripts/lancer-sur-android.sh --sans-corpus  # sans régénérer dist/
#
# C'est le pendant de `lancer-sur-iphone.sh` et `lancer-sur-le-mac.sh`, et il
# existe pour la même raison qu'eux : **vérifier sur la machine plutôt que de
# consommer une place de livraison.**
#
# Android n'a pas le quota quotidien d'Apple, mais il a pire — un `versionCode`
# est brûlé **définitivement** dès qu'il est téléversé, y compris pour une
# release de test supprimée. Une poussée réflexe ne coûte pas une journée
# d'attente, elle coûte un numéro qu'on ne récupère jamais.
#
# ## Pourquoi ce script existe alors qu'un `./gradlew` suffirait
#
# Il ne suffit pas. Deux pannes de machine tuent la commande **avant** qu'elle
# démarre — `jenv` qui réclame un JDK absent, et l'absence de `local.properties`
# dans un arbre neuf. Les deux ont coûté un diagnostic cette semaine, et aucune
# ne ressemble à sa cause. `gradle-de-la-chaine.sh` les ferme, et ce script le
# source : c'est ce qui rend la chaîne reproductible au lieu de dépendre de ce
# qu'on a dans son shell.
#
# ## Le corpus, et pourquoi il est régénéré par défaut
#
# L'app lit `app/Resources/data`, que `corpus.sh` remplit depuis le vault. Sans
# cette étape, on installe une app dont le texte date du dernier passage — et
# c'est invisible : rien à l'écran ne dit que le corpus est vieux.
#
# `--sans-corpus` l'évite quand on ne touche qu'à l'interface et qu'on vient de
# le construire.

set -euo pipefail
cd "$(dirname "$0")/.."

. "$(dirname "$0")/gradle-de-la-chaine.sh"

corpus=1
for arg in "$@"; do
    case "$arg" in
        --sans-corpus) corpus=0 ;;
        *) printf 'argument inconnu : %s\n' "$arg" >&2; exit 2 ;;
    esac
done

if [ "$corpus" = 1 ]; then
    printf '→ le corpus\n'
    ./scripts/corpus.sh
fi

# Un appareil, sinon rien. `adb install` sur zéro appareil rend un message qui
# parle de périphérique et non d'absence — on le dit ici, clairement.
if ! adb devices | tail -n +2 | grep -q "device$"; then
    printf '⚠ aucun appareil Android joignable.\n' >&2
    printf '  Brancher le téléphone (débogage USB), ou démarrer un émulateur\n' >&2
    printf '  depuis le Device Manager d'"'"'Android Studio.\n' >&2
    exit 1
fi

printf '→ construction et installation\n'
(cd android && ./gradlew --no-daemon :app:installDebug)

printf '→ lancement\n'
adb shell monkey -p com.labibleont.ont -c android.intent.category.LAUNCHER 1 >/dev/null

printf '✓ lancée sur %s\n' "$(adb devices | tail -n +2 | grep 'device$' | head -1 | cut -f1)"
