# Créer les trois comptes OAuth

Tout est prêt côté code. Il reste ce que je ne peux pas faire à votre place :
créer les identifiants sur trois portails, à votre nom.

**L'adresse de retour est déjà en ligne**, la même pour Google et GitHub :

```
https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com/auth/google/callback
https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com/auth/github/callback
```

Vérifiez-la si vous voulez, elle répond déjà :

```bash
curl -i "https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com/auth/google/callback?code=TEST"
# → 302  location: ont://auth/callback?provider=google&code=TEST
```

---

## 1. Apple — plus simple que prévu

**Vous n'avez pas besoin de Services ID.** Je m'étais trompé en le disant, et
la correction change la marche à suivre.

La raison : quand le code d'autorisation vient de l'**interface native**
(Face ID, pas un navigateur), Apple l'accorde à l'app elle-même. Le
`client_id` de l'échange doit donc être l'**identifiant de l'app**, et un
Services ID provoquerait un `invalid_grant`. C'est confirmé par Apple :

> *« The client_id used when calling the token endpoint should match the
> native app's app id. The services ID should not be used here and using that
> would result in failure due to mismatch. »*

Un Services ID ne redeviendra nécessaire que le jour où il y aura une version
web.

### Ce qui est déjà fait

✅ **L'App ID `com.labibleont.ONT` est enregistré**, avec la capacité
**Sign in with Apple** activée, et un profil de provisionnement créé. Xcode
s'en est chargé lors d'une compilation avec `-allowProvisioningUpdates` :
l'autorisation étant déclarée dans `app/ONT.entitlements`, il a activé la
capacité correspondante sur le portail.

✅ **Team ID : `N49VNC2G57`**, relevé sur le certificat de signature de cette
machine, et déjà posé dans `app/project.yml`.

### Ce qu'il reste — une seule chose

Sur [developer.apple.com](https://developer.apple.com/account/resources) :

1. **Keys → nouvelle clé**
   Un nom quelconque, cocher **Sign in with Apple**, la rattacher à l'App ID
   ci-dessus, puis télécharger le fichier `.p8`.
   ⚠️ **Il n'est téléchargeable qu'une seule fois.** Rangez-le tout de suite
   dans votre gestionnaire de mots de passe.
   Noter le **Key ID** affiché (10 caractères).
C'est la seule étape Apple qui n'a pas d'équivalent en ligne de commande :
Apple ne propose aucune API pour créer une clé de connexion.

### Ce que ça donne

| Variable | Valeur |
|---|---|
| `APPLE_CLIENT_ID` | `com.labibleont.ONT` ✅ connu |
| `APPLE_TEAM_ID` | `N49VNC2G57` ✅ connu |
| `APPLE_KEY_ID` | le Key ID de la clé |
| `APPLE_PRIVATE_KEY` | le contenu du `.p8` |

**Aucune URL de retour à déclarer** pour le flux natif.

### Côté Xcode

✅ Rien à faire : `app/ONT.entitlements` porte la capacité, et
`DEVELOPMENT_TEAM` est renseigné. L'app se signe déjà pour appareil réel.

---

## 2. Google

Sur [console.cloud.google.com](https://console.cloud.google.com/apis/credentials) :

1. Créer un projet, ou en réutiliser un.
2. **Écran de consentement OAuth** : type « Externe », nom de l'app
   « La Bible ONT », adresse d'assistance. Portées demandées : `openid` et
   `email`, rien de plus.
3. **Identifiants → Créer → ID client OAuth → Application Web**

   ⚠️ **« Application Web », pas « iOS ».** Un client iOS chez Google est un
   client *public* : il n'a pas de secret, et notre architecture repose
   justement sur un secret gardé côté serveur. Le client Web nous en donne un.

4. **URI de redirection autorisé** :
   ```
   https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com/auth/google/callback
   ```

| Variable | Où |
|---|---|
| `GOOGLE_CLIENT_ID` | Lambda **et** `app/project.yml` → `ONTGoogleClientID` |
| `GOOGLE_CLIENT_SECRET` | Lambda **seulement** |

L'identifiant client n'est pas un secret — il voyage dans l'URL d'autorisation
que le navigateur affiche. Le *secret*, lui, ne doit jamais entrer dans l'app.

---

## 3. GitHub

Sur [github.com/settings/developers](https://github.com/settings/developers) →
**OAuth Apps → New OAuth App** :

| Champ | Valeur |
|---|---|
| Application name | La Bible ONT |
| Homepage URL | votre site, ou l'URL de l'API en attendant |
| Authorization callback URL | `https://j451hq8d3k.execute-api.eu-west-3.amazonaws.com/auth/github/callback` |

Puis **Generate a new client secret**.

| Variable | Où |
|---|---|
| `GITHUB_CLIENT_ID` | Lambda **et** `app/project.yml` → `ONTGitHubClientID` |
| `GITHUB_CLIENT_SECRET` | Lambda **seulement** |

---

## 3 bis. GitHub, pour le site — **une adresse de plus, pas une application**

Le champ du portail s'appelle « Authorization callback **URLs** », au pluriel,
et porte un bouton **Add more**. Une même application sert donc les deux
origines, avec **le même `client_id` et le même secret**.

Sur l'application `La Bible ONT`, **Edit** → *Add more* :

    https://ontbible.com/fr/compte/retour

puis **Update application**. Rien d'autre ne bouge : ni variable, ni code.

> **Ce README a dit le contraire, et c'était faux.** Il annonçait une seconde
> application, un second identifiant et un second secret, au motif que GitHub
> n'admettrait qu'une adresse de retour. C'était vrai autrefois ; le portail ne
> l'est plus, et c'est l'auteur qui l'a vu en ouvrant la page.
>
> GitHub avertit en revanche de ne **pas** compter sur la tolérance des
> sous-chemins de la première adresse : *« please register multiple URLs rather
> than rely on legacy support for subdirectories »*. On enregistre donc chaque
> adresse en entier.

## 3 ter. Apple, le Services ID

Pour la même raison inverse : un code venu d'un navigateur a été accordé au
**Services ID**, jamais à l'App ID. Présenter l'un pour l'autre rend
`invalid_grant`, **dans les deux sens**.

Le Services ID existe déjà — `com.labibleont.ont.webapp`, domaine
`ontbible.com`, retour `https://ontbible.com/fr/compte/retour`. La clé `.p8`
sert aux deux flux : c'est l'identité qui change, pas la signature.

| Variable | Où |
|---|---|
| `APPLE_SERVICES_ID` | Lambda **seulement** |

**Tant que ces trois variables manquent**, le backend répond au site
`503 fournisseur non configuré` — jamais un refus. Le site sait donc que la
faute est chez nous, au lieu de la chercher chez lui devant un `invalid_grant`.
C'est éprouvé par `le_site_se_dit_non_configure_tant_que_ses_identites_manquent`.

Elles n'entrent volontairement **pas** dans la précondition Terraform qui garde
les identifiants de l'app : leur absence est un état légitime, celui où le site
n'est pas encore branché.

---

## 4. Tout brancher

```bash
./scripts/configurer-oauth.sh
```

Le script demande les valeurs manquantes — l'App ID et le Team ID sont déjà
pré-remplis — vérifie la forme de chacune, lit le `.p8` depuis son chemin,
déploie la Lambda, pose les identifiants publics dans `project.yml`, régénère
le projet, puis interroge les trois fournisseurs.

Il est relançable : une valeur déjà saisie est proposée par défaut.

### Ce qu'il vous dira

```
✓ apple — le fournisseur répond
✓ google — le fournisseur répond
✗ github — injoignable : vérifiez les identifiants
```

Un **401** signifie que le fournisseur a répondu et a refusé le code bidon :
c'est le bon signe. Un **502** signifie qu'il n'a pas été joint — les
identifiants ne sont pas pris en compte. La différence entre les deux vous dit
exactement où vous en êtes.

Ensuite, dans l'app : onglet **Vous → Continuer avec…**

---

## Ce qui protège le flux

**Le secret ne quitte jamais la Lambda.** L'app n'envoie que le code
d'autorisation ; c'est le backend qui le troque. Un `.ipa` se désassemble en
dix minutes — un secret qui s'y trouverait serait public.

**PKCE, pour Google et GitHub.** Le code revient à l'app par un schéma d'URL
`ont://`, et une autre app installée sur l'appareil pourrait déclarer le même
schéma et l'intercepter. Elle le présenterait alors à *notre* backend et
obtiendrait une session.

PKCE ferme cette porte : l'app tire un secret au hasard (le *vérificateur*),
n'en envoie que l'empreinte SHA-256 (le *défi*) au fournisseur, et ne révèle
le secret qu'au moment de l'échange. **Un code volé sans son vérificateur ne
vaut rien.** Apple n'en a pas besoin — son flux natif ne passe par aucune URL.

**La revue App Store.** « Continuer avec Apple » doit figurer, et en premier,
dès qu'un autre fournisseur tiers est proposé. C'est déjà le cas dans l'écran.
