# L'Xcode de la chaîne — la stable, quand elle est là.
#
# À SOURCER, pas à exécuter : `. "$(dirname "$0")/xcode-de-la-chaine.sh"`,
# après le `cd` d'en-tête du script appelant.
#
# ## Pourquoi ce fichier existe
#
# La machine de l'auteur SÉLECTIONNE la bêta (`xcode-select` → Xcode-beta.app),
# et c'est voulu : elle sert à explorer macOS. Mais la CI compile avec la
# dernière STABLE, et le Swift des deux accepte des programmes différents —
# mesuré sur la promotion #216 : l'init synthétisée d'une struct `private` à
# clôture `@ViewBuilder` compilait en bêta et rougissait en stable. « 33
# épreuves vertes » en local avait laissé partir une PR rouge.
#
# Décision de l'auteur du 17 septembre 2026, Xcode 27.0 stable installé à
# côté de la bêta : **les scripts de CE dépôt compilent avec la stable, la
# sélection globale ne bouge pas.** `DEVELOPER_DIR` prime sur `xcode-select`
# pour `xcodebuild`, `xcrun`, `notarytool`, `stapler` — tout ce que ces
# scripts invoquent.
#
# ## Les deux replis, et pourquoi dans cet ordre
#
# - déjà posé dans l'environnement → respecté : qui appelle avec un
#   `DEVELOPER_DIR` explicite sait ce qu'il fait, et la CI n'a pas ce fichier
#   à contourner ;
# - stable absente → on n'invente rien : la sélection globale s'applique, et
#   on le DIT — un aiguillage silencieux vers la bêta recréerait la
#   divergence qu'il existe pour fermer, en pire, parce qu'invisible.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        printf '⚠ pas de stable en /Applications/Xcode.app — la sélection globale s'"'"'applique : %s\n' \
            "$(xcode-select -p)" >&2
    fi
fi
