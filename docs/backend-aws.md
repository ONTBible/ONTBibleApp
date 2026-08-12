# Backend ONT — plan et chiffrage AWS

*Plan seulement, aucun code écrit. Tarifs vérifiés le 11 août 2026, région de référence us-east-1 ; Paris (eu-west-3) coûte 5 à 10 % de plus.*

---

## Ce que le backend doit faire

Trois choses, et rien d'autre pour l'instant :

1. **Authentifier** — Apple, Google, GitHub.
2. **Synchroniser** ce que le lecteur produit — surlignages, notes, position de lecture. Le volume est minuscule : quelques centaines d'objets de 200 octets par personne.
3. **Servir le Qahal** — verset du jour partagé, compteurs de reprise, plus tard les échanges.

Ce qu'il ne doit **pas** faire : servir le corpus. Le texte voyage dans le binaire de l'app (1,4 Mo). La lecture reste entièrement hors ligne, et c'est un choix, pas une limitation — une liseuse de Bible qui ne s'ouvre pas dans le métro a raté son sujet.

## L'architecture

Le modèle de Pinkha convient, avec une correction :

```
app iOS ──HTTPS──▶ API Gateway HTTP API ──▶ Lambda (Rust ou Node) ──▶ DynamoDB
                            │
                            └── autorisateur JWT
```

- **API Gateway HTTP API**, pas REST API. Même service, 1,00 $ le million de requêtes contre 3,50 $ — soit 71 % de moins pour exactement ce dont on a besoin. Le REST API n'apporte ici que des fonctions qu'on n'utilisera pas.
- **Lambda** sur ARM (Graviton), 256 Mo. En Rust si vous voulez réutiliser l'écosystème de Pinkha : démarrage à froid de quelques millisecondes contre ~200 ms en Node.
- **DynamoDB en on-demand**, table unique. `PK = user#<id>`, `SK = hl#<unité>#<verset>` ou `pos`. Pas de provisionnement à gérer, pas de capacité à surveiller.
- **Synchronisation** : dernier écrit gagné, horodaté par objet. Poussée à la modification (avec temporisation), récupération à l'ouverture. Le corps complet d'un utilisateur tient en une réponse — inutile d'inventer un protocole delta.

---

## Le chiffrage

Hypothèse de trafic : **10 appels d'API par utilisateur et par jour**, ce qui est généreux pour une app de lecture (l'essentiel se passe hors ligne).

| | 100 lecteurs | 5 000 lecteurs | 50 000 lecteurs |
|---|---:|---:|---:|
| Requêtes / mois | 30 000 | 1,5 M | 15 M |
| API Gateway HTTP | 0,03 $ | 1,50 $ | 15,00 $ |
| Lambda (requêtes + durée) | 0 $ | 0,10 $ | 5,67 $ |
| DynamoDB (écritures + lectures) | 0,02 $ | 0,44 $ | 4,38 $ |
| CloudWatch Logs | ~0 $ | 0,50 $ | 5,00 $ |
| **Sous-total infrastructure** | **0,05 $** | **2,54 $** | **30,05 $** |
| **Cognito** | 0 $ | 0 $ | **600,00 $** |
| **Total** | **≈ 0 $** | **≈ 2,50 $** | **≈ 630 $** |

Le franchissement du seuil gratuit sur les briques de calcul est indolore : Lambda offre 1 M de requêtes et 400 000 Go-seconde par mois, à perpétuité, et DynamoDB 25 Go de stockage.

### Le vrai poste de dépense n'est pas celui qu'on croit

À 50 000 lecteurs, **Cognito représente 96 % de la facture**. L'infrastructure de calcul coûte 30 $ ; l'authentification, 600 $.

Le mécanisme : Cognito facture 0,015 $ par utilisateur actif mensuel au-delà de 10 000 gratuits. Le palier gratuit ne s'applique qu'aux connexions directes et aux fournisseurs **sociaux** intégrés — Apple, Google, Amazon, Facebook. **GitHub n'en fait pas partie** : il passe par OIDC générique, dont le palier gratuit est de **50 utilisateurs par mois**. Autrement dit, avec GitHub via Cognito, vous payez dès le 51ᵉ lecteur qui s'en sert.

### Deux options

**Option A — Cognito.** Vous ne codez pas l'authentification, la rotation des jetons, la révocation. Gratuit jusqu'à 10 000 lecteurs. Au-delà, cher, et GitHub est une anomalie tarifaire à lui seul.

**Option B — échange OAuth dans Lambda, jetons signés par vous.** Une fonction reçoit le code d'autorisation Apple/Google/GitHub, le troque contre l'identité chez le fournisseur, et émet votre propre JWT court signé par une clé dans Secrets Manager. Vous possédez le format, aucun fournisseur ne vous taxe à l'utilisateur, et les trois providers coûtent pareil.

| | Option A (Cognito) | Option B (JWT maison) |
|---|---:|---:|
| 5 000 lecteurs | 2,50 $ | 3,00 $ |
| 50 000 lecteurs | 630 $ | **~31 $** |
| Développement | ~1 jour | ~4 jours |

**Ma recommandation : option B.** Le surcoût de développement est de trois jours ; l'économie est d'un facteur vingt dès qu'il y a du monde. Et ce n'est pas de la cryptographie faite maison — c'est l'échange OAuth standard plus une signature JWT avec une bibliothèque éprouvée. Le vrai risque de sécurité (garder des mots de passe) n'existe pas ici : ce sont les fournisseurs qui authentifient.

Si vous préférez démarrer vite, l'option A est raisonnable **à condition de ne proposer qu'Apple et Google au lancement** — GitHub attendra. Migrer de Cognito vers des jetons maison plus tard est faisable mais oblige à recréer les comptes.

---

## Deux choses à trancher avant d'écrire une ligne

**1. Vos données sont juridiquement sensibles.** Les surlignages et les notes d'un lecteur de Bible, rattachés à une identité, sont des données qui **révèlent des convictions religieuses**. Le RGPD les classe en catégorie particulière (article 9) : leur traitement est interdit par principe, sauf consentement explicite, et exige des garanties renforcées — chiffrement, minimisation, purge, portabilité.

Ce n'est pas un détail administratif, ça a trois conséquences concrètes :
- l'hébergement en **eu-west-3 (Paris)**, pas en Virginie ;
- un **consentement explicite et séparé** pour la synchronisation — donc la synchronisation doit être **facultative**, l'app restant pleinement utilisable sans compte ;
- l'export et la suppression du compte, pour de vrai.

C'est aussi un argument produit : « vos annotations restent sur votre appareil sauf si vous demandez la synchronisation » est une position solide, et elle est déjà vraie aujourd'hui.

**2. Le Qahal change la nature du projet.** Un verset du jour partagé et des compteurs, c'est de l'infrastructure triviale. Des échanges entre lecteurs, c'est de la modération, du signalement, une politique de contenu — et l'App Store l'exige dès qu'il y a du contenu généré par les utilisateurs. À budgéter en temps, pas en dollars.

---

## Comment je procéderais

1. **Rien tout de suite.** Surlignages et position fonctionnent déjà en local et sont écrits en `Codable` — le fichier de sauvegarde *est* déjà le corps de la future requête de synchronisation.
2. **Quand vous voudrez un compte** : option B, un seul point d'entrée (`POST /auth/:provider`, `GET|PUT /sync`), une table DynamoDB, une Lambda. Deux à trois jours.
3. **Le Qahal ensuite**, quand la question de la modération sera tranchée.

Le coût réel avant quelques milliers de lecteurs est de l'ordre de **quelques euros par mois**. Le domaine et le compte développeur Apple (99 $/an) coûteront plus cher que l'infrastructure pendant longtemps.
