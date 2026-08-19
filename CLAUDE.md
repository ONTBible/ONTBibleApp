# ONTBibleApp — le pipeline, la liseuse iOS, le backend

> ## À faire à la fin de **chaque** travail, sans exception
>
> Ce dépôt est l'un des **trois** d'un même projet — avec `ONTBibleTranslation`
> (le vault) et `ONTBibleWebapp` (`ontbible.com`). Ils sont côte à côte :
> `~/ONTBible/<dépôt>`.
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

**La branche nomme un destinataire, pas une manœuvre.** `dev` livre au groupe
interne, `staging` aux testeurs invités, `main` à la revue de l'App Store. On ne
saute pas un palier — `branch-policy.yml` le tient.

**`main` est protégée, les commits sont signés, on passe par pull request.** Les
trois dépôts portent le même ruleset.
