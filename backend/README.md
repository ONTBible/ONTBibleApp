# Backend ONT

Lambda Rust derrière une API Gateway HTTP API, DynamoDB en table unique.
Même modèle que le proxy Notion de Pinkha.

**Jetons maison, pas Cognito** — le raisonnement complet est dans
`src/domain/token.rs` et dans `../docs/backend-aws.md`. En une phrase : Cognito
facture *par personne*, tout le reste facture *par requête*, et à 50 000
lecteurs ça faisait 600 $ contre 30 $.

```bash
cargo test                                        # 21 tests, sans réseau ni AWS
cargo run                                         # http://127.0.0.1:3000
cargo lambda build --release --arm64 --output-format zip
```

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

## Ce qu'il vous reste à créer

Je ne peux pas le faire à votre place : ce sont des comptes à votre nom.

### 1. Apple — le plus long des trois

Sur [developer.apple.com](https://developer.apple.com/account/resources) :

1. **Identifiers → Services ID** — en créer un (ex. `com.labibleont.signin`).
   Ce n'est **pas** l'identifiant de l'app. Activer « Sign in with Apple ».
2. Dans sa configuration, déclarer l'URL de retour :
   `https://<api-id>.execute-api.eu-west-3.amazonaws.com/auth/apple/callback`
   (HTTPS obligatoire, donc à renseigner **après** le premier `terraform apply`).
3. **Keys** → nouvelle clé, activer « Sign in with Apple », télécharger le
   `.p8`. **Il n'est téléchargeable qu'une fois.** Noter le *Key ID*.
4. Noter le *Team ID* (en haut à droite du portail).

Apple est le seul à ne pas donner de secret statique : le secret est un JWT
ES256 qu'on fabrique à chaque échange à partir du `.p8` — c'est fait dans
`providers.rs::apple_client_secret`.

### 2. Google

[console.cloud.google.com](https://console.cloud.google.com/apis/credentials) →
identifiants OAuth 2.0, type « Web application ». Même URL de retour. Récupérer
`client_id` et `client_secret`.

### 3. GitHub

[github.com/settings/developers](https://github.com/settings/developers) → OAuth
App. Même URL de retour. Récupérer `client_id` et `client_secret`.

## Déploiement

```bash
export TF_VAR_jwt_secret="$(openssl rand -base64 48)"   # à garder — le perdre déconnecte tout le monde
export TF_VAR_apple_client_id="com.labibleont.signin"
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

Le compte IAM utilisé (`pinkha-app`) aura besoin des droits de création sur
DynamoDB, Lambda, IAM, API Gateway et CloudWatch Logs — à vérifier au premier
`plan`.

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

## Ce qui reste à faire

- Le client Swift (`AuthClient` + `SyncClient`) et l'écran de connexion.
- La bascule du `Store` local vers la synchronisation, derrière le consentement.
- Le premier `terraform apply`, quand vous aurez les identifiants.
