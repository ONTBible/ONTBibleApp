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

## #328 · Inscrire le `cd` qui échoue en silence, et la garde qui le rattrape

    ouverte le   21 septembre 2026, par iOS
    vers         device
    état         ouverte

**Pourquoi.** Deux sessions se sont fait prendre le même jour à quatre heures
d'écart : un `cd` vers un worktree disparu échoue, écrit une ligne, et les
commandes suivantes s'exécutent dans le dossier d'avant. La première a mesuré
trois fois la branche d'une autre session ; la seconde a déplacé la branche de
l'arbre principal. ==La seconde avait lu le récit de la première le matin même==
— c'est l'argument pour que ce soit tenu par une garde et non par la mémoire.

**Ce que ça engage.** Rien de technique : c'est du journal, et il vaut pour les
trois dépôts puisque les huit sessions partagent la machine. La garde est à
deux lignes et ne demande aucun outil.

**Pour la relire.** Le second contrôle — `git rev-parse --show-toplevel` — n'est
pas redondant avec `pwd` : `pwd` ment quand le dossier a été recréé entre-temps,
et `--show-toplevel` répond à la question réelle avant un commit, ==à quel dépôt
on parle==. Et le déclencheur, les deux fois, était un worktree disparu sous les
pieds : ==un dossier de travail n'est pas un lieu stable==.

---

## #330 · Rendre la photo de profil visible dans son onglet, et lui donner un menu

    ouverte le   22 septembre 2026, par iOS
    vers         device
    état         fusionnée le 22 septembre 2026 — `5a0e9aa`

**Pourquoi.** Trois défauts du même écran, ==dont deux se déguisaient en autre
chose==. Le disque bordeaux de l'onglet « Vous » **était** la photo, peinte en
aplat de la teinte : une image opaque ne rend pas une silhouette, elle rend un
rond plein qu'on prend pour l'icône d'un compte absent. Et « Apple » sortait
deux fois plus gros que sa pomme, parce que `.font(nil)` réinitialise au lieu
d'hériter.

**Ce que ça engage.** `ONTUI.ligneDeListe` est un rôle du design system, et son
piège est maintenant écrit dessus : ==à ne poser que sur le contenu direct
d'une ligne de liste==. Le site le reprend en portant la typographie — sa
notion de « police nulle » n'existe pas en CSS, où l'héritage est le défaut ;
c'est donc un cas où la transposition **ne doit pas** être littérale.

Gravatar ajoute un appel réseau sortant depuis l'app, vers `gravatar.com`.
Aucune adresse n'y voyage : l'empreinte SHA-256 seulement.

**Pour la relire.** La garde du mode de rendu ==existait, et son commentaire
disait juste== — elle était posée sur la `Image` de SwiftUI quand la barre
d'onglets, vue UIKit, ne lit que le mode de l'`UIImage`. Raison juste, endroit
faux : c'est la forme qui coûte le plus cher à trouver, parce que la garde
paraît tenue. Le premier correctif (la dépendance observable manquante) était
juste aussi, et insuffisant seul : ==il a fallu les deux==.

---

## #327 · Inscrire que l'or des intraduisibles est sous le seuil, et assumé

    ouverte le   21 septembre 2026, par iOS
    vers         device
    état         fusionnée le 21 septembre 2026 — `ad10f1a`

**Pourquoi.** `ONTColors.accent` rend **3,11:1** sur le parchemin et 3,39:1 sur
le blanc. WCAG demande 3:1 pour ce qu'on repère et **4,5:1 pour ce qu'on lit** —
et c'est du texte qu'on lit : `ONTTypography.term` porte cet or à la taille du
corps, dans le fil de la phrase. Relevé par le site en portant les quatre
thèmes, confirmé par macOS qui a nommé deux emplois texte de plus.

**Aucune valeur ne change.** Trois builds réels sur le simulateur ont mis les
trois ors sous l'œil de l'auteur — 3,11 · 4,50 · 6,40 — et il a gardé le
premier en connaissant la mesure. La PR n'inscrit que le commentaire.

**Ce que ça engage.** Le site et macOS ont mesuré le même écart le même jour.
==Leur garde de contraste s'aligne sur ce choix et non sur la norme== : sans
ça elle rougit tous les jours sans rien apprendre, et une garde qu'on apprend à
ignorer ne garde plus rien. Le site porte la sienne dans son PR #156.

**Pour la relire.** La décision « l'or se repère au lieu de se lire » existait
déjà dans `accentSurSurlignage` — mais elle avait été prise **pour le numéro de
verset**, et s'est étendue à l'intraduisible sans être reprise. C'est la forme
qu'on se signale depuis une semaine : ==une décision juste dans son périmètre
d'origine, devenue fausse en s'étendant sans qu'on la repose==.

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
