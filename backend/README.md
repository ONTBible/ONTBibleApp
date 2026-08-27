# Backend ONT

Lambda Rust derrière une API Gateway HTTP API, DynamoDB en table unique.
Même modèle que le proxy Notion de Pinkha.

**Jetons maison, pas Cognito** — le raisonnement complet est dans
`src/domain/token.rs` et dans `../docs/backend-aws.md`. En une phrase : Cognito
facture *par personne*, tout le reste facture *par requête*, et à 50 000
lecteurs ça faisait 600 $ contre 30 $.

```bash
cargo test                                        # 25 tests, sans réseau ni AWS
cargo run                                         # http://127.0.0.1:3000
cargo lambda build --release --arm64 --output-format zip
```

**Il est en ligne**, sur `api.ontbible.com` comme sur son adresse
`execute-api` — un domaine régional d'API Gateway devant la même fonction. Le
nom stable existe pour ne plus dépendre de l'identifiant `execute-api`, qu'AWS
change si l'API est recréée ; l'app, elle, appelle encore l'adresse brute
(`ONTAPIBaseURL` dans `app/project.yml`), et la bascule se fait au rythme des
publications.

`.github/workflows/deployer-backend.yml` remplace le **code** de la Lambda à
chaque `main`. Il ne touche jamais à Terraform — `main.tf` porte d'ailleurs
`ignore_changes` sur le code, sans quoi un `apply` lancé d'un poste remettrait
en production le zip qui traîne dans le dossier local.

## Routes

```
POST   /auth/apple|google|github   { code, redirect_uri } → session
POST   /auth/refresh               { refresh_token }      → session
GET    /sync?since=<ms>                                   → surlignages + position
PUT    /sync                       { highlights, position }
DELETE /me                                                 effacement (RGPD)
GET    /health
```

Une session, c'est `{ access_token, refresh_token, expires_in, created }`. Le
jeton d'accès vit **1 heure** (il est irrévocable, donc court) ; celui de
rafraîchissement vit **60 jours**, ne sert qu'**une seule fois**, et se
révoque puisqu'il est en base.

## Les trois fournisseurs — **créés**, le 11 août 2026

Apple, Google et GitHub sont configurés ; leurs identifiants vivent dans
`terraform/oauth.env`, gitignoré. La marche à suivre complète, avec les
adresses de retour exactes et les pièges de chaque portail, est dans
**`../docs/comptes-oauth.md`**. Deux choses à ne pas réapprendre :

**Apple ne demande pas de Services ID.** Ce README a dit le contraire, et
c'était faux : quand le code d'autorisation vient de l'**interface native**
(Face ID, pas un navigateur), Apple l'accorde à l'app elle-même. Le `client_id`
de l'échange doit donc être l'identifiant de l'app — `com.labibleont.ONT` — et
un Services ID provoquerait un `invalid_grant`. Apple le dit lui-même.

**Ce jour est arrivé le 27 août 2026** : `ontbible.com` signe des comptes, et le
Services ID redevient nécessaire — *pour le site seulement*. Le backend choisit
donc l'identité selon l'origine du code (voir la section suivante).

### Deux origines, deux identités

Le corps de `POST /auth/{fournisseur}` porte un champ `origine` : `"app"` ou
`"webapp"`. **Absent vaut `"app"`** — les versions déjà installées ne l'envoient
pas et ne le pourront jamais rétroactivement ; un défaut à `"webapp"` les casserait
toutes le jour du déploiement.

**`webapp` et non `web`** : le dépôt s'appelle `ONTBibleWebapp` et le Services
ID `com.labibleont.ont.webapp`. Un nom qui traverse trois dépôts vaut mieux
unique — un troisième mot pour la même chose ferait chercher lequel fait foi.

| fournisseur | app | site | ce que ça coûte |
|---|---|---|---|
| **Apple** | App ID `com.labibleont.ONT`, `redirect_uri` **omis** | Services ID `com.labibleont.ont.webapp`, `redirect_uri` **envoyé** | un identifiant de plus ; la clé `.p8` sert aux deux |
| **GitHub** | la même application | la même application | rien — une adresse de retour de plus |
| **Google** | le même client | le même client | rien — une adresse de retour de plus dans la console |

**Apple est le seul des trois à distinguer.** Google sert les deux origines
avec le même client ; GitHub aussi, une même application pouvant porter
plusieurs adresses de retour. C'est pourquoi Google a été branché en premier,
et pourquoi GitHub ne coûte qu'un clic.

Les variables à poser, en plus de celles de l'app. **Elles vivent dans
`terraform/main.tf`**, pas dans une commande : l'environnement de la Lambda est
décrit là, et un `aws lambda update-function-configuration` serait effacé au
prochain `apply`.

    APPLE_SERVICES_ID          com.labibleont.ont.webapp

Elle se pose dans `oauth.env`, que `scripts/deployer-backend.sh` source.

**GitHub n'en demande aucune** : son portail accepte plusieurs adresses de
retour par application — le champ est au pluriel, avec un « Add more » —, donc
l'app et le site partagent identifiant et secret. Il suffit d'ajouter
`https://ontbible.com/fr/compte/retour` à l'application existante.

La marche à suivre est dans `../docs/comptes-oauth.md`, §3 bis et §3 ter.

**Une identité manquante se dit.** Sans elle, la route rend
`ProviderNotConfigured` — 503, « fournisseur non configuré » — et non un refus.
Le site saurait ainsi que la faute est chez nous, au lieu de la chercher chez
lui devant un `invalid_grant`. C'est éprouvé par
`le_site_se_dit_non_configure_tant_que_ses_identites_manquent`.

Apple est en revanche le seul à ne pas donner de secret statique : le secret est
un JWT ES256 fabriqué à chaque échange depuis le `.p8` — voir
`providers.rs::apple_client_secret`. La clé `.p8` n'est **téléchargeable qu'une
fois**, et Apple ne propose aucune API pour la recréer.

**Google en client « Application Web », jamais « iOS ».** Un client iOS chez
Google est un client *public* : il n'a pas de secret, et toute l'architecture
repose sur un secret gardé côté serveur. L'identifiant client, lui, n'est pas
un secret — il voyage dans l'URL d'autorisation, et il est posé dans
`app/project.yml`. Le *secret* ne va que dans la Lambda.

## Déploiement

L'infrastructure existe. Ce qui suit est la recette complète — pour la relire,
pour la rejouer ailleurs, ou pour comprendre ce qu'un `apply` va faire.

```bash
export TF_VAR_jwt_secret="$(openssl rand -base64 48)"   # à garder — le perdre déconnecte tout le monde
export TF_VAR_apple_client_id="com.labibleont.ONT"      # l'App ID, pas un Services ID
export TF_VAR_apple_team_id="XXXXXXXXXX"
export TF_VAR_apple_key_id="YYYYYYYYYY"
export TF_VAR_apple_private_key="$(cat AuthKey_YYYYYYYYYY.p8)"
export TF_VAR_google_client_id="…"
export TF_VAR_google_client_secret="…"
export TF_VAR_github_client_id="…"
export TF_VAR_github_client_secret="…"

cargo lambda build --release --arm64 --output-format zip
cd terraform && terraform init && terraform apply
```

`terraform output api_url` donne l'URL à reporter dans le `Secrets.xcconfig`
de l'app iOS. Aucun secret ne doit jamais entrer dans le binaire iOS : c'est
toute la raison d'être de ce proxy — un `.ipa` se désassemble.

Un premier `apply` peut se faire **sans aucun identifiant OAuth** : l'API
répond, `/health` fonctionne, et vous obtenez l'URL nécessaire pour configurer
les trois fournisseurs. Deuxième `apply` ensuite, avec les secrets.

Le compte IAM utilisé (`ont-app`, profil local `[ont]`) a besoin des droits de
création sur DynamoDB, Lambda, IAM, API Gateway et CloudWatch Logs — c'est la
politique `ont-deploy`, la même qui sert au site, **étendue** plutôt que
doublée.

**L'état Terraform vit en local**, et il n'y a pas de dépôt distant. C'est ce
qui interdit à la CI d'exécuter Terraform : un job qui le ferait travaillerait
sans savoir ce qui existe déjà.

## Décisions à ne pas défaire sans le savoir

**Région Paris.** Les surlignages d'un lecteur de Bible révèlent des
convictions religieuses : catégorie particulière au sens de l'article 9 du
RGPD. D'où aussi : synchronisation **facultative**, consentement explicite et
séparé, et `DELETE /me` qui efface pour de vrai. L'app doit rester pleinement
utilisable sans compte — c'est le cas aujourd'hui.

**Dernier écrit gagné**, arbitré par verset. Un surlignage est un objet
minuscule qu'une seule personne modifie depuis ses propres appareils : une
fusion à trois branches serait de la complexité sans bénéfice. Voir
`domain/sync.rs::resolve`.

**Référence `(unité, verset)` et jamais un décalage de caractères.** Une
révision du texte déplacerait les caractères et rendrait les surlignages faux ;
un numéro de verset reste juste.

**Vérification du jeton dans le processus**, pas par un autorisateur API
Gateway : l'autorisateur intégré n'accepte que des jetons asymétriques via
JWKS, et un autorisateur Lambda ajouterait une invocation facturée par requête.

**Limite de débit sur l'API dès le premier jour.** Sans elle, une boucle dans
une version de l'app transforme une facture de 3 $ en facture à trois chiffres
pendant la nuit.

## Le côté app

Fait, et les trois pièces sont là :

| | |
|---|---|
| `ONTData/Remote/Services.swift` | les clients HTTP — auth et synchronisation |
| `ONTData/Remote/KeychainSessionStore.swift` | la session, dans le trousseau |
| `YouFeature/…/SignInFlow.swift` + `AccountModel.swift` | la connexion, le consentement, la fusion |

Les DTO du transport sont **distincts** des types du domaine, délibérément : le
backend compte le temps en millisecondes et porte une pierre tombale `deleted`
que le stockage local n'a pas. Les mélanger ferait remonter des contraintes de
transport jusque dans le domaine.

Et le **consentement est distinct du fait d'avoir un compte** : on peut être
connecté sans que rien ne parte. `AccountModel.sync()` refuse tant que les deux
ne sont pas vrais.

## Ce qui reste ouvert

- **La bascule de l'app vers `api.ontbible.com`.** `ONTAPIBaseURL` pointe encore
  l'adresse `execute-api` ; les deux répondent, et le changement se fait avec
  une publication.
- **Le `.p8` d'Apple n'existe qu'en un exemplaire.** Le perdre demande d'en
  créer un autre et de redéployer ; perdre `TF_VAR_jwt_secret` déconnecte tout
  le monde d'un coup. Les deux méritent leur place dans un gestionnaire de mots
  de passe, pas seulement sur ce disque.
