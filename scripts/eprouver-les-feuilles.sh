#!/usr/bin/env bash
# Une feuille de l'ONT passe par le système de design, jamais par `.sheet` nu.
#
# ## Le défaut que ça ferme
#
# Le 8 septembre 2026, la feuille de prononciation s'ouvrait **plein écran** et
# sans poignée, pendant que celle de lecture s'ouvrait à mi-hauteur avec
# poignée. Deux feuilles de la même app, deux comportements.
#
# La cause n'était pas une faute d'écriture. L'habillage existait —
# `ontHauteurDeFeuille` —, et **il fallait y penser au point d'appel**. Une
# feuille sur sept l'appelait.
#
# L'habillage est maintenant porté par `ontFeuille`. Mais un `.sheet` nu le
# contourne toujours, et rien ne le dirait : l'écart ne se voit qu'en ouvrant
# les deux feuilles à la suite, sur un appareil, en y pensant.
#
# ## Ce que ce contrôle mesure, et ce qu'il ne mesure pas
#
# Une **forme** : la présence de `.sheet(` hors du système de design. Il ne dit
# rien de ce que la feuille contient, ni de son thème. C'est étroit, et c'est
# assumé — la seule chose qu'il attrape est précisément celle qui s'oublie.
#
# Le système de design a le droit, lui : c'est son travail.
set -euo pipefail
cd "$(dirname "$0")/.."

hors_du_systeme() {
  git ls-files 'app/*.swift' \
    | grep -v '^app/Packages/ONTDesignSystem/' \
    | xargs grep -n "$1" 2>/dev/null || true
}

fautifs=$(hors_du_systeme '\.sheet(')

if [ -n "$fautifs" ]; then
  echo "::error::Une feuille présentée hors du système de design."
  echo
  echo "$fautifs"
  echo
  echo "Ces appels contournent \`ontFeuille\`, donc l'habillage de l'ONT :"
  echo "les paliers mi-hauteur puis plein écran, et la poignée qui les annonce."
  echo "Une feuille qui ne les porte pas ne ressemble pas aux autres, et rien"
  echo "ne le dit avant qu'on ouvre les deux à la suite."
  echo
  echo "Le geste : remplacer par \`.ontFeuille(...)\`. Si cette feuille veut"
  echo "vraiment autre chose, l'écrire — \`paliers: .pleine\`, ou"
  echo "\`paliers: .mesures([...])\`. Une dérogation se lit, un oubli non."
  exit 1
fi

# ## Et le style de liste, pour la même raison
#
# Le lendemain du même écran : la feuille de prononciation touchait les deux
# bords pendant que celle de lecture respirait. Un `Form` groupé porte les
# marges du système, un `.listStyle(.plain)` n'en porte aucune — et rien dans
# le code ne dit lequel des deux on voulait.
#
# Deux intentions nommées le disent maintenant : `ontListeDeProse` pour ce qui
# se lit, `ontListeDIndex` pour ce qui se parcourt. **Nommer plutôt
# qu'exempter** : une liste sans gouttière est soit un index, soit un oubli, et
# une liste d'exceptions vieillit là où un nom tient.
nus=$(hors_du_systeme '\.listStyle(\.plain)')

if [ -n "$nus" ]; then
  echo "::error::Un style de liste nu, hors du système de design."
  echo
  echo "$nus"
  echo
  echo "Un \`.listStyle(.plain)\` ne porte aucune marge latérale sur iOS : la"
  echo "liste touche les deux bords. C'est juste pour un index, faux pour de la"
  echo "prose — et la forme nue ne dit pas lequel des deux on voulait."
  echo
  echo "Le geste : \`.ontListeDeProse()\` pour ce qui se lit — une fiche, une"
  echo "feuille, des résultats —, \`.ontListeDIndex()\` pour ce qui se parcourt"
  echo "au pouce le long d'un rail."
  exit 1
fi

echo "toutes les feuilles passent par le système de design"
