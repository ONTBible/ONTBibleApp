# La chaîne Gradle de ce dépôt — le JDK de la CI, et le SDK qu'on a.
#
# À SOURCER, pas à exécuter : `. "$(dirname "$0")/gradle-de-la-chaine.sh"`,
# après le `cd` d'en-tête du script appelant. C'est le pendant Android de
# `xcode-de-la-chaine.sh`, et il existe pour la même raison : **un outil nu ne
# compile pas ce que la CI compile.**
#
# ## Les deux pannes qu'il ferme, mesurées les 10 et 14 septembre 2026
#
# **`jenv` réclame un JDK qui n'est pas là.** Il demande `temurin64-25.0.2`, que
# la machine n'a pas, et toute commande Gradle meurt AVANT d'avoir rien lancé :
#
#     jenv: version `temurin64-25.0.2' is not installed
#
# Aucun `.java-version` du dépôt ne le fixe — c'est un réglage de la machine. Le
# symptôme ne ressemble pas à sa cause : on croit à un défaut de build.
#
# **Un arbre neuf n'a pas de `local.properties`.** Le fichier porte `sdk.dir` et
# il est ignoré par git, délibérément : le chemin du SDK dépend de la machine, et
# le committer le rendrait faux ailleurs — en silence. Un `git worktree add`
# donne donc un arbre qui ne compile pas, sur une erreur qui ne dit pas qu'il
# suffit d'un fichier :
#
#     SDK location not found. Define a valid SDK location with an
#     ANDROID_HOME environment variable or by setting the sdk.dir path…
#
# ## Le JDK : celui de la CI, pas le plus récent
#
# `tests.yml` pose `java-version: '21'`. On vise donc **temurin-21** et non le 26
# installé à côté : la seule version qui prédise le résultat de la CI est celle
# que la CI emploie. Prendre « le plus récent » recréerait la divergence que ce
# fichier existe pour fermer.
#
# ## Les replis, et pourquoi dans cet ordre
#
# - déjà posé dans l'environnement → respecté. Qui appelle avec un `JAVA_HOME`
#   explicite sait ce qu'il fait, et **la CI n'a rien à contourner** : elle pose
#   le sien par `setup-java` ;
# - absent → on n'invente pas : on prévient et on laisse la sélection de la
#   machine s'appliquer. Un aiguillage silencieux vers un autre JDK serait pire
#   que la panne, parce qu'invisible.

if [ -z "${JAVA_HOME:-}" ]; then
    _jdk_de_la_ci="/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
    if [ -d "$_jdk_de_la_ci" ]; then
        export JAVA_HOME="$_jdk_de_la_ci"
        export PATH="$JAVA_HOME/bin:$PATH"
    else
        printf '⚠ temurin-21 introuvable — la sélection de la machine s'"'"'applique.\n' >&2
        printf '  La CI compile en 21 ; un autre JDK ne prédit pas son résultat.\n' >&2
    fi
    unset _jdk_de_la_ci
fi

# Le SDK : on écrit `local.properties` s'il manque, jamais s'il est là.
#
# L'écrire par-dessus effacerait un réglage que l'auteur a posé pour une raison
# qu'on ne connaît pas. On ne remplit qu'un vide.
if [ ! -f android/local.properties ]; then
    for _sdk in "$ANDROID_HOME" "$HOME/Library/Android/sdk" \
                "/opt/homebrew/share/android-commandlinetools"; do
        if [ -n "$_sdk" ] && [ -d "$_sdk/platforms" ]; then
            printf 'sdk.dir=%s\n' "$_sdk" > android/local.properties
            printf '→ android/local.properties écrit : %s\n' "$_sdk" >&2
            break
        fi
    done
    unset _sdk
    if [ ! -f android/local.properties ]; then
        printf '⚠ aucun SDK Android trouvé — Gradle refusera de configurer.\n' >&2
        printf '  Poser ANDROID_HOME, ou installer le SDK par Android Studio.\n' >&2
    fi
fi
