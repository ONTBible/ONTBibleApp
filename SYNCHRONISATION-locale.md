# Le journal local de ce dépôt

Ce que ce dépôt a appris **pour lui seul** — une feuille qui ne se ferme pas
d'un clic à côté, une barre flottante construite puis écartée, un crasheur posé
la veille. Des choses vraies et utiles, qui n'engagent aucun des deux autres
dépôts.

**Pourquoi elles ne voyagent pas.** `SYNCHRONISATION.md` est le journal commun,
et il est **identique dans les trois dépôts** : il devient une copie engendrée
depuis le vault, et une copie engendrée ne peut porter que ce que sa source
porte. Y laisser six cents lignes de barres latérales macOS obligerait à les
verser dans le vault de la traduction — ce que l'en-tête de ce journal-là refuse
en toutes lettres : *pas un changelog du dépôt*.

Jusqu'ici la séparation était une marque, `*(local)*` en fin de titre, que le
contrôle de concordance retirait avant de comparer. Elle est désormais
**physique**. La marque reste dans les titres ci-dessous, telle qu'elle a été
écrite.

**Où va une entrée qui concerne les trois dépôts.** Dans `SYNCHRONISATION.md`,
au journal, et nulle part ici. Le critère est celui de sa section « Tronc commun
et entrées locales » : une entrée qui traverse a quelque chose à *dire* aux
autres — quoi, à qui, ce que ça change — et elle le dit dans son corps. Une
entrée qui n'a rien à leur dire reste ici.

**Dans le doute, elle traverse.** Une entrée locale qui aurait dû voyager est
une leçon que les deux autres n'apprendront jamais, et personne ne s'apercevra
qu'elle leur manque. Une entrée du tronc qui n'avait pas à voyager n'est qu'une
ligne de trop.

L'ordre est chronologique, comme dans le journal commun : il se lit dans l'ordre
où les choses ont été apprises.

---

## 3 septembre 2026 — une feuille du Mac ne se ferme pas d'un clic à côté *(local)*

Deux captures, deux griefs : « le bas de l'interface est pas ouf, en plus cliquer
à l'extérieur ne ferme pas la modal ». Les deux sortent de la **présentation**,
et aucun n'est réparable depuis le contenu.

- **Le bandeau gris.** Un `ToolbarItem(.confirmationAction)` posé dans une
  `.sheet` du Mac descend dans une barre qu'**AppKit** dessine, en gris du
  système, sous une carte qui porte l'aubergine. Ni `presentationBackground` ni
  le thème ne l'atteignent : la barre est hors de la vue.
- **Le clic à côté.** Une feuille du Mac est modale à sa fenêtre par
  construction. Il n'existe pas d'API pour la refermer d'un clic dehors — ce
  n'est pas un réglage manquant, c'est ce qu'est une feuille.

D'où `ONTFeuille` : sur iOS `.sheet` reste `.sheet`, à l'identique ; sur le Mac
l'app dessine la carte, avec le voile, la croix et ⎋.

### Ce qui traverse

**La règle vaut pour les trois plateformes, pas seulement pour le Mac** : une
modale se ferme au clic à côté. iOS l'a par le glissement, le Mac vient de
l'avoir — **et Android l'avait déjà**, vérifié plutôt que supposé : ses trois
modales (`MainActivity.kt:961`, `:976`, `:987`) sont des `ModalBottomSheet` de
Material 3, dont le tap sur le voile appelle `onDismissRequest`, et les trois y
vident bien leur état.

Rien à porter, donc. Ça méritait d'être écrit quand même : le jour où l'une
d'elles deviendrait une `Surface` posée à la main, elle perdrait le geste sans
que rien ne le dise — c'est un défaut de la présentation, invisible dans le
contenu, exactement comme celui qu'on vient de corriger ici.

### La surimpression est la sœur, pas la fille

Posée **après** `.ontTheme(from:)`, la carte sortait en clair sur une app en
aubergine, et son voile — dont l'opacité dépend du mode — devenait invisible.
Le contenu d'un `.overlay` est le frère de la vue à laquelle on l'attache : il
ne voit pas l'environnement que les modificateurs d'avant ont posé.

Vu à la capture, invisible à la lecture. C'est aussi pourquoi la carte se rend à
la **racine** et non au point d'appel : dans un `NavigationSplitView`, un voile
posé dans `ChapterView` s'arrêterait au bord de la barre latérale, qui resterait
allumée et cliquable sous une modale.

### Ce qui n'a pas pu être éprouvé, et pourquoi c'est écrit

**Le clic dans le voile lui-même ne l'a pas été.** Un poseur d'événements
CoreGraphics a été écrit ; il ne passe pas — l'accessibilité est refusée sur
cette machine, comme à `osascript`. Les captures d'avant et d'après le clic sont
identiques au bit près, y compris en visant la croix : cela ne prouve rien sinon
que l'événement n'arrive pas.

Les trois épreuves gardées portent donc sur ce que le clic **appelle** : que le
geste déposé est bien celui qu'on rend, que retirer n'enlève que la sienne, et
que c'est la dernière posée qui se dessine. Chacune a été retournée contre son
propre défaut — geste jeté, `removeAll()`, `.first` au lieu de `.last` — et
rougit sur lui seul.

## 3 septembre 2026 — le tour des quatorze vues, et le crasheur que la veille avait posé *(local)*

« L'app macOS paraît rigide, formes strictes ; iOS est fluffy, rebondie. » Le
constat de l'auteur, vérifié en capturant **chaque vue** du Mac — quatorze — et
quatre références iPad, en planche-contact.

### Ce que la planche a montré

- **le mouvement d'abord** : tout le Mac bougeait en `easeOut` 0,12–0,18 s, une
  rampe qui s'arrête net ; l'iPhone bouge en ressorts. Aucune animation du Mac
  ne rebondissait, pas une. D'où `ONTMouvement` — trois ressorts nommés
  (`ressort`, `ressortVif`, `arrivee`) au lieu de valeurs posées sur place ;
- **les formes** : cartes à 22 pt + liseré d'1 px + Divider sec, contre la
  feuille iPad à ~40 pt sans bordure. D'où `ONTRadius.feuille` (34), l'ombre
  seule, le filet du thème ;
- **la taille figée** : la carte faisait 66 % × 84 % de la fenêtre quel que soit
  le contenu — la note flottait dans 500 pt de vide. Le plafond se pose
  **après** la peinture : `frame(maxHeight:)` s'étire jusqu'à sa borne (la
  règle du `maxWidth: .infinity`), et peint avant lui, le fond suivait.

### Trois défauts fonctionnels, qu'on ne voit qu'en regardant chaque vue

- la **note** : « Annuler / Enregistrer » projetés dans la barre de la
  *fenêtre*, à 400 pt de la carte. Sur le Mac elle a maintenant sa mise en page
  propre, boutons dans la carte ;
- la **recherche** : son *champ* projeté pareil — `.searchable` est un vœu
  adressé à la barre d'outils la plus proche, et dans une surimpression c'est
  celle de la fenêtre. D'où `ONTChampDeRecherche`, le champ des cartes ;
- le **sélecteur** : trois captures identiques — l'app *morte*. Un
  `NavigationStack` qui pousse une étape inscrit son bouton retour dans le
  `NSToolbar` de la fenêtre ; dans une surimpression, l'insertion lève une
  exception en plein layout et AppKit abat le processus
  (`AppKitToolbarStrategy.update` sous `_insertNewItemWithItemIdentifier:`).

### Le crasheur venait de la veille, et la leçon est là

La migration `.sheet` → carte (la veille au soir) avait éprouvé quatre modales
et pas le sélecteur — le seul dont la pile **pousse** à l'ouverture. La règle
qui en sort : **dans une carte du Mac, pas de `NavigationStack` qui navigue**.
Le sélecteur garde son modèle d'étapes (`chemin`) et le rend à la main,
transitions au ressort, retour dans la carte. Ce qui projette vers la barre de
fenêtre — toolbar, searchable, bouton retour — n'a rien à faire dans une
surimpression.

### Ce qui traverse

Rien de `dist/` ni du schéma. Android : ses modales sont des `ModalBottomSheet`
Material, le système y tient la chrome — la classe de défaut n'existe pas
là-bas. Le chantier suivant est décidé avec l'auteur : micro-animations
(survol, pression) sur tout ce qui se clique, et la palette en **gammes
50→900** à la Tailwind avec les rôles sémantiques (accent, danger…) par-dessus
— ancrée sur les couleurs relevées du logo et du site, pas redessinée.

## 3 septembre 2026 — la refonte du mouvement, couche des fondations *(local)*

L'auteur, designer : « en termes d'UI/UX motion design on est loin, je veux une
refonte ». Ses références : Craft, CleanMyMac pour la densité de micro-
animations, ChatGPT iOS pour la tenue du branding. Sa signature, choisie sur
deux options : **rebond assumé** (amortis 0,66–0,78, dépassement visible). Sa
dose : « limite trop — si y en a trop c'est moi qui te dirai ».

### La gamme, générée et ancrée

`ONTGamme` — six teintes × onze crans (50→950), interpolées en **OKLCH** autour
des couleurs relevées : `#421B26` **est** `aubergine800`, `#CDBE83` **est**
`or300`, la nuit du site **est** `aubergine950`, au bit près. Trois teintes
fonctionnelles accordées à la DA : `braise` (danger — terre cuite qui penche
bordeaux), `cedre` (succès — sauge boisée), `ambre` (avertissement). Le
générateur vit hors dépôt ; ses contrastes sont vérifiés à la génération **et**
re-vérifiés par `GammeContrastTests`, qui a refusé le cèdre 600 (4,4:1 sur
parchemin) avant qu'il ne soit committé — le rôle prend le 700.

Les rôles passent par le thème : `theme.danger`, `theme.succes`,
`theme.avertissement` + leurs surfaces, et deux voiles d'interaction nommés
(`voileSurvol` 7 %, `voilePression` 13 % d'encre).

### Les états d'interaction, qui n'existaient pas

Vingt-quatre `buttonStyle(.plain)` dans l'app du Mac, **aucun état de
pression**. `ONTInteraction` pose : `ONTPresse` (l'échelle cède, l'encre se
voile, le ressort ramène — `.ontPresse` / `.ontLigne`), `ontSurvol(dans:)` (le
voile épouse la forme, levée optionnelle), `ontApparition(_:)` (la cascade de
Craft — huit points plus bas, remonte au `pop`, décalée par le rang, bornée au
douzième).

Appliqué : cases du sélecteur (survol levé + pression + cascade des grilles
d'unités et de versets), segments (pression + glissement du choisi au ressort),
barre latérale (pression rejoint le survol), boutons de cadre des fiches, croix
des feuilles, balai du champ de recherche.

### Ce qui traverse

**iOS reçoit les mêmes jetons** — la gamme, les rôles, `ONTMouvement` — mais la
cascade et les survols sont posés là où iOS a déjà ses réponses système ; rien
ne double. Le site : sa palette CSS et la gamme partagent les ancres — le jour
où `ontbible.com` veut ses crans, la gamme se transpose en variables CSS depuis
le même générateur. Android : les initiatives restent à iOS ; le portage des
jetons attendra que la refonte soit arbitrée ici.

### Reste à faire, dit à l'auteur

Les listes en cartes par ligne (corpus, lexique, Vous, résultats), les rangées
restantes (NavigationLink du corpus), l'orchestration d'arrivée des écrans, le
survol des intraduisibles dans le texte, la pastille de la barre. Vue par vue,
planche à l'appui.

## 4 septembre 2026 — la reprise sans geste, et deux écrans passés en cartes *(local)*

### « Impossible de swiper » — les deux chemins, encore

L'auteur, depuis la vue Reprendre : ni la traîne au clic maintenu, ni le
glissement à deux doigts. `RepriseDeLecture` rendait **`ChapterView` nu**, quand
le chemin du sommaire rend `ChapterSwipe` — l'enveloppe qui porte le geste
horizontal. La même unité glissait par une porte et pas par l'autre. C'est le
motif « deux chemins, une vue » du 30 août, revenu par une porte de plus ; le
balayage n'a trouvé aucun autre `ChapterView` nu.

L'audit demandé (« scrute tout ») sur la classe cible-partielle : les rangées du
lexique et les cases de versets portaient déjà leur `contentShape` ; les
`DisclosureGroup` ont tous quitté le Mac ; les `onTapGesture` restants couvrent
leur boîte entière.

### Lexique et Vous en cartes par ligne

La leçon du lexique : deux `listRowBackground` sur la même rangée, c'est
**l'intérieur** qui gagne — le `clear` posé par-dessus n'éteignait pas la
surface d'`ontRow`, et les cartes se noyaient dans un bloc. D'où
`ontLigneDeCarte()`, un seul appel qui choisit par plateforme, au lieu de deux
qui s'empilent. Et le style : la `List` était déjà `.plain` — le bloc n'était
pas le style groupé, c'était nous.

Vous : chaque rangée sa carte, l'échec de connexion en **braise dans sa
pastille** (`theme.danger` sur `dangerSurface`) au lieu du `.red` système,
« Supprimer mon compte » teinté braise, capsules de connexion avec levée au
survol et pression. Les capsules ont servi le soir même : l'auteur s'est
connecté avec Apple sur le Mac — première connexion réussie de la plateforme.

## 4 septembre 2026 — la barre qui flotte pour de vrai, et l'interface qui répond au doigt *(local)*

« Tu te moques de moi pour la sidebar ? » — et le reproche était juste : le
panneau flottant avait été posé, mais la barre peignait encore son fond opaque
par-dessus la vitre. Un demi-pas livré comme un pas. La leçon est celle
d'`implementer-plutot-que-declarer`, version visuelle : une translucidité
annoncée dont rien ne traverse.

### La vitre, la vraie

`NSVisualEffectView` en `.behindWindow` — pas un matériau SwiftUI, qui ne
floute que ce que la fenêtre dessine : la translucidité de Craft traverse la
**fenêtre**, c'est le bureau qu'on devine. Voile aubergine à 0,65 par-dessus
(à 0,5, mesuré sur capture, la barre tirait au gris du système), coins 18,
marges 12, filet qui prend la lumière. La barre elle-même ne peint **plus
rien** — quatre jours de `background(theme.surface)` retirés.

### L'anneau qui se déplaçait

Le focus initial de la fenêtre a montré l'anneau du système sur la carte
« Reprendre », puis — celle-ci l'ayant décliné — sur le bouton de barre
d'outils, cerceau mauve au lancement sur les captures de l'auteur. Éteindre
l'anneau élément par élément ne faisait que le déplacer : la fenêtre s'ouvre
maintenant **sans premier répondeur**.

### Le ratio volé par les captures

`defaultSize` portait déjà le 1,29 relevé sur la référence de l'auteur — mais
chaque campagne de captures forçait 1440 × 900, et la restauration d'état le
gardait : les lancements normaux rouvraient au format App Store. Le mode
capture pose désormais `isRestorable = false`. Un outil de mesure qui modifie
l'état qu'il mesure — la troisième fois que ce motif coûte, après la vignette
de Stage Manager et le garde-fou qui mesurait la fenêtre d'avant.

### Les haptiques et le verre

`ONTHaptique` — tic (pression), cran (plis, segments), palier (cartes) — sur
le moteur que `ChapterSwipe` éprouvait déjà. Câblé dans `ONTPresse` même :
tout bouton au style de la maison sonne, sans site à instrumenter.
`ontVerre(dans:)` pose le verre du système (macOS 26, matière fine en repli)
sur ce qui flotte au-dessus du texte — la pastille de lecture d'abord. Sur
iOS, les deux ne font rien : le système y donne déjà ses retours.

## 4 septembre 2026 — le survol par mot, et l'attribut qui ne voyageait pas *(local)*

La table d'un livre et les résultats de recherche ont rejoint les cartes par
ligne — même recette, cascade comprise ; la carte du Qahal a pris la pression.
Le morceau qui se raconte est ailleurs : **le survol des intraduisibles**, mot
à mot, dans un `Text` de SwiftUI qui n'offre rien pour ça.

### Le mécanisme

`TextRenderer` (macOS 15) : le point du curseur descend dans le rendu, chaque
run du layout expose ses indices de caractères, et le run marqué qui contient
le point reçoit son voile avant d'être dessiné. Pas de relayout — du dessin.
Posé sur le mode étude seulement : sur la prose continue, chaque mouvement de
souris redessinerait le chapitre entier, et c'est le canon de performance.

### L'attribut qui ne voyageait pas — l'épreuve l'a tué avant un lecteur

Premier essai : une double conformité `TextAttribute` + `AttributedStringKey`,
en espérant que la marque voyage de l'`AttributedString` jusqu'aux runs du
layout. **Elle ne voyage pas.** Et rien ne l'aurait dit : un attribut perdu
donne exactement l'écran d'un survol au repos.

D'où le mode **sonde** — tous les runs marqués voilés, sans curseur — et une
épreuve de pixels : sonde et repos doivent différer sur un texte qui porte un
terme, et rester identiques sur un texte qui n'en porte pas. Elle a rougi du
premier coup sur la double conformité, et c'est elle qui a imposé le chemin
qui marche : des **plages de caractères** extraites de la chaîne finale
(césures comprises), passées au rendu comme données, recollées aux runs par
`CharacterIndex` — opaque, mais `Strideable` : le minimum du layout est le
caractère zéro, `distance(to:)` rend chaque index absolu. Le minimum et non le
premier run : l'hébreu en RTL réordonne les runs visuellement.

## 4 septembre 2026 — la barre flottante, construite puis écartée en main *(local)*

Trois états en une soirée : la barre opaque, la barre flottante à la Craft
(coins, marges, ombre, sol unifié), puis — l'auteur l'ayant prise en main —
le retour au **bord à bord** : « on voit que ce rendu est pas natif, ça fait
bizarre ». Il avait raison sur la sensation : les barres du Mac sont des
colonnes, pas des cartes.

Ce qui reste du voyage est le morceau qui comptait : la **translucidité** —
`NSVisualEffectView` en `.behindWindow`, le bureau qui se devine, le voile
aubergine à 0,65 — et une barre qui ne peint plus son propre fond. Le détour
n'était pas gratuit : c'est en la voyant flotter qu'on a su que ce n'était pas
elle. Décision d'auteur, consignée pour que personne ne la reconstruise.

## 4 septembre 2026 — la toile et les deux panneaux : Craft, lu pour de bon *(local)*

« Non, la sidebar Craft elle flotte, mec. » Exact — et la relecture de sa
capture a montré ce que la première tentative avait raté : **ce n'est pas la
barre qui flotte, c'est tout ce que la fenêtre porte**. Chez Craft, la fenêtre
est une toile plus sombre, et DEUX panneaux y sont posés — la barre *et* le
contenu — coins ronds fins, retraits de ~8 pt, ni bordure ni ombre : la
séparation se fait au ton.

C'est pour ça que la version « carte flottante » sonnait faux : un panneau
seul contre une page pleine est un objet collé sur un mur. Le flottement est
un écosystème, pas une propriété d'objet.

Construit : `Toile` (marge 8, coin 12), `PanneauDeBarre` (vitre arrière +
voile 0,65, découpé), `PanneauDeContenu` (la page de lecture, découpée),
`CouleurDeToile` (le fond du thème sous un voile noir à 0,35). Deux pièges
mesurés au passage : la matière-système de la colonne remplissait les marges
avec la même vitre que le panneau — marges posées, marges invisibles — et il
faut recouvrir son sol comme pour la page ; et une prévisualisation réduite
écrase un écart de ton réel (14,6,8 contre 48,37,40 au pixel) — juger les
retraits fins à l'échelle 1.

## 4 septembre 2026 — la mesure a clos le débat de la barre *(local)*

L'entrée précédente (« deux panneaux sur une toile ») était la **troisième
lecture fausse** de la même capture. L'auteur a corrigé une fois de plus — « les
trois boutons sont dans la sidebar chez Craft » — et cette fois la capture a été
**balayée au pixel** au lieu d'être relue à l'œil :

    bord gauche   : fenêtre → barre (76), sans gouttière
    zone des feux : posés SUR la barre — elle monte jusqu'au bord
    barre→contenu : 76 → 59 sur ~20 pt → 35
    bord droit    : 35 → 59 sur ~23 pt → fenêtre

**La barre est soudée ; c'est la page qui flotte**, posée sur une toile visible
en gouttière, et la hiérarchie des tons est barre > toile > page. Transposé
dans la peau : 48 > 30 > 22, vérifié sur notre propre capture au même balayage.

Quatre allers-retours pour une capture qui était là depuis le début. La leçon
est celle de toute la semaine : **une référence visuelle se mesure, elle ne se
relit pas** — l'œil a affirmé trois architectures différentes du même écran,
le balayage en a établi une en trente lignes.

## 4 septembre 2026 — la bidouille retirée : la barre est celle du système *(local)*

Fin du feuilleton de la barre, sur l'ordre de l'auteur : « enlève la bidouille ».
`PanneauFlottant.swift` est supprimé — vitre à la main, voile, toile, page en
panneau — et le `NavigationSplitView` rend sa colonne au système, qui la fait
translucide tout seul depuis que la barre ne peint plus son propre fond.

Le solde net de l'aller-retour tient en deux lignes de vrai : **la barre ne
peint plus rien** (c'était l'opacité d'origine, le seul vrai défaut), et la
fouille — SDK balayé, web croisé, deux sondes — a établi qu'il n'existe pas
d'API « barre flottante » : sur cette machine, la forme native est la colonne
de verre pleine hauteur, et ce qui flotte chez Craft est leur page. Quatre
constructions écrites, une gardée : celle du système.
