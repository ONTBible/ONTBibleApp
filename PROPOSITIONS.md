# Les propositions — ce qui est ouvert, par qui, et ce que ça engage

**Décision de l'auteur du 21 septembre 2026.** Toute PR s'inscrit ici, **par
celle qui l'ouvre**, avec ce qu'aucun tableau GitHub ne montre : pourquoi elle
existe, et ==ce qu'elle engage chez les voisins==.

## Pourquoi ce fichier, à côté de `DECISIONS.md`

`DECISIONS.md` porte ce qui est ==tranché== ; celui-ci porte ce qui est
==proposé et attend==. Une PR *est* une proposition — le nom dit ce qu'elle est,
et le couple dit où chaque chose vit.

**Ce qu'un tableau de PR ne donne pas**, et qui manque à chaque relecture :

- **qui l'a ouverte.** Les huit sessions poussent sous le compte `gloiiire` :
  `gh pr list --author @me` rend ==toutes les PR du dépôt==. Trois sessions y
  sont tombées le même jour. ==L'auteur git ne distingue personne== ;
- **pourquoi.** Le titre dit ce que la PR fait, jamais le défaut qu'elle répare
  ni la mesure qui l'a rendue nécessaire ;
- **ce qu'elle engage.** C'est la règle du `CLAUDE.md` racine — *demander ce que
  ce travail change pour les autres dépôts* — et rien ne la portait. ==Un
  changement de forme dans une réponse casse une plateforme qui n'est pas celle
  qu'on regarde en le faisant.==

## Ce que ça coûte : rien

==L'entrée voyage dans la PR qu'elle décrit.== On l'écrit sur la branche qu'on
vient de pousser, avant d'ouvrir la PR — pas de commit de plus, pas de CI de
plus, pas de fusion supplémentaire à attendre.

C'est la différence avec la déclaration d'un worktree, qui coûte un aller-retour
parce qu'elle ne s'attache à aucun travail en cours.

## La forme

    ## #NNN · le titre
    
        ouverte le   la date, par le RÔLE — jamais un nom de session
        vers         la branche de base
        état         ouverte · fusionnée le … · abandonnée le …
    
    **Pourquoi.** Le défaut, et la mesure qui l'a rendu visible.
    
    **Ce que ça engage.** Ce qui traverse vers les autres dépôts, ce qui
    devient irréversible, ce qu'une autre session devra reprendre.
    
    **Pour la relire.** Ce qu'il faut savoir qu'on ne devinerait pas.

==On ne retire pas une entrée quand la PR est fusionnée== : on change son état
et on date. Une proposition abandonnée reste, avec le motif — ==c'est souvent
elle qui a le plus à apprendre==.

**Et on n'écrit pas le « pourquoi » d'une PR qu'on n'a pas ouverte.** Une entrée
peut donc porter ==*à écrire par qui l'a ouverte*== : ce trou-là est une
information, et il se voit.

---

## #326 · Déclarer son worktree, puisque rien ne le prouve

    ouverte le   21 septembre 2026, par la manageuse
    vers         device
    état         ouverte

**Pourquoi.** Rien ne prouve qu'une session tient un worktree : `herdr agent
list` rend le dossier de *lancement*, `lsof` ne voit rien entre deux tours, et
la date de l'index vieillit sur un poste où l'on lit sans commiter. Les trois
ont été éprouvées, les trois échouent. Un démontage de cinq worktrees a failli
emporter un commit qui ne tenait que par l'un d'eux.

**Ce que ça engage.** Le texte est identique dans les trois dépôts — tronc
commun. Le **contrôle** vit dans le vault (`cartographier-la-flotte.py
--worktrees`) : l'app et le site portent la règle, pas l'instrument.

**Pour la relire.** La table déclare **un poste, pas une branche** — trois
sessions l'ont demandé le même jour, et la raison la plus forte est d'Android :
*un avertissement qu'on apprend à ne plus lire abîme tous les autres*.

## #313 · Le dépôt a ses chuqqot, et on répare depuis elles

    ouverte le   18 septembre 2026, par la manageuse
    vers         device
    état         ouverte

**Pourquoi.** Consigne de l'auteur : se fier aux énoncés gravés pour construire,
et réparer en remontant à l'énoncé qu'un défaut contredit plutôt que par un cas
particulier. L'entrée porte huit formes d'un même défaut, toutes relevées le
même jour, **chacune par une session sur elle-même**.

**Ce que ça engage.** Tronc commun, texte identique dans les trois dépôts. Elle
a été rebasée une fois sur `device` après un conflit d'ajout — quatre entrées du
18 écrites en parallèle, **gardées toutes les quatre**.

**Pour la relire.** Une clause y a été rétablie le 20 : elle n'avait jamais été
écrite alors que je l'avais annoncée portée.

## #302 · Aligner le titre de Chuqqot, refuser deux fiches sur une clé

    ouverte le   13 septembre 2026
    vers         device
    état         ouverte, CI rouge sur `tests`

*À écrire par qui l'a ouverte.* Son worktree `ONTBibleApp-journal13` porte
**non réclamé** à la table : personne ne s'en est déclaré tenant quand la
question a été posée.
