# ONTBibleApp — le pipeline, la liseuse iOS, le backend

> ## À faire à la fin de **chaque** travail, sans exception
>
> Ce dépôt est l'un de ceux d'un même projet, rangés côte à côte sous
> `~/ONTBible/` — avec `ONTBibleTranslation` (le vault) et `ONTBibleWebapp`
> (`ontbible.com`). La racine porte son propre `CLAUDE.md`, qui se charge
> aussi ici : **ouvrir les sessions depuis `~/ONTBible/`**, les voisins sont
> alors visibles.
>
> Avant de dire qu'un travail est fini, **lire [`SYNCHRONISATION.md`](SYNCHRONISATION.md)
> et appliquer sa règle** : demander ce que ce travail change pour les deux
> autres dépôts, le porter chez eux dans la même session, et inscrire la ligne
> au journal.
>
> Ce n'est pas une politesse entre dépôts. Un format de sortie modifié ici casse
> la compilation du site, qui lit `dist/` directement ; une couleur retouchée
> là-bas fait diverger la peau de l'app. Rien de tout cela ne se voit depuis le
> dépôt où l'on travaille.

---

## Où est le reste

`README.md` porte l'architecture, le contrat des trois niveaux, les modules, le
schéma engendré, les tests, et l'état du corpus au dernier build. Il fait foi.

Ce fichier ne redit rien de ce qu'il contient — deux documents qui décrivent la
même chose finissent par se contredire, et personne ne sait alors lequel croire.

| | |
|---|---|
| l'architecture, les modules, les tests | `README.md` |
| ce qui traverse les trois dépôts | `SYNCHRONISATION.md` |
| les gestes — corpus, captures, déploiement | `scripts/`, chacun documenté en tête |
| la fiche App Store et sa livraison | `.github/scripts/`, `.github/workflows/livraison.yml` |

## Ce qui ne se devine pas

**L'auteur se nomme Gloire Bikouta en public.** Jamais « Sha'eliel » : c'est son
nom interne au vault, et il n'en sort pas. Le déposant légal — INPI, contrats —
est Yannis Bikouta.

**`ONT.xcodeproj` et `Schema.swift` ne sont pas committés.** Ils sont engendrés,
respectivement par `xcodegen` depuis `project.yml` et par le pipeline depuis
`schema.rs`. Committer un fichier engendré, c'est garantir qu'il divergera de sa
source le jour où quelqu'un le corrigera à la main.

**La branche nomme un destinataire, pas une manœuvre.** Et depuis le 31 août
2026 elle le nomme jusqu'au bout : `main` et `staging` disaient une manœuvre,
pas un destinataire.

    device  →  dev  →  beta-test  →  app-store

| branche | qui reçoit |
|---|---|
| `device` | **personne** — les appareils de l'auteur, par `scripts/lancer-sur-*` |
| `dev` | le groupe de test interne |
| `beta-test` | les testeurs invités |
| `app-store` | la revue d'Apple |

On ne saute pas un palier — `branch-policy.yml` le tient.

**`device` ne livre rien**, et c'est tout son intérêt. Apple limite les
téléversements **par plateforme et par jour** : le 31 août, dix des onze places
de la journée sont parties sur `dev`, et c'est la promotion vers les testeurs
qui s'est fait refuser. On vérifie donc sur l'appareil, et l'on ne consomme une
place que pour ce qui la mérite.

**Les trois autres sont protégées et se fusionnent sur décision de l'auteur** —
`dev` compris, depuis le même jour et pour la même raison. `device` porte les
signatures et interdit la réécriture, mais pas la pull request : c'est la voie
de travail.

**Les commits sont signés partout.** Les trois dépôts portent le même ruleset.
