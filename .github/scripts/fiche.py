#!/usr/bin/env python3

"""Remplit la fiche App Store, et y téléverse les captures.

Se lance par le workflow **Fiche**, qui porte les clés :

    gh workflow run fiche.yml -f captures=true

ou à la main, si on les a sous le coude :

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_PRIVATE_KEY="$(cat AuthKey_….p8)" \\
      ./.github/scripts/fiche.py --captures

Rejouable : il reprend la version en préparation, la crée si aucune n'attend,
et remplace les jeux de captures au lieu de les empiler.

## Pourquoi automatiser une fiche qu'on ne remplit qu'une fois

Parce qu'on ne la remplit pas une fois. Le sous-titre se retouche, les captures
se refont à chaque changement visuel, et la description se corrige. Chaque
retouche à la main est une occasion de laisser la fiche décrire une version qui
n'existe plus — c'est exactement le défaut que `scripts/captures.sh` évite du
côté des images.

## Ce qu'il fait, et ce qu'il ne peut pas faire

| | |
|---|---|
| sous-titre, description, mots-clés, adresses | ✅ |
| droits sur le contenu | ✅ |
| classement d'âge | ✅ |
| **captures d'écran** | ✅ — les huit, aux deux tailles |
| **confidentialité** (les étiquettes) | ❌ interface web seulement |
| **statut de commerçant** (DSA) | ❌ interface web seulement |

Les deux dernières ne sont pas exposées par l'API d'Apple. Elles restent à
faire à la main, et sans elles la soumission est refusée.
"""

import argparse
import hashlib
import pathlib
import re
import sys

import requests

from asc import API, Client, application

RACINE = pathlib.Path(__file__).resolve().parents[2]
CAPTURES = RACINE / "app" / "Captures"
PROJET = RACINE / "app" / "project.yml"

# Les états d'une version qu'on a encore le droit de modifier. Repris de
# `soumettre.py`, qui les tient pour la même raison.
MODIFIABLES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")

# Les deux tailles qu'Apple exige, et le nom qu'il leur donne. Il redimensionne
# lui-même pour les écrans plus petits : ces deux-là suffisent.
FORMATS = {
    "iphone-6.9": "APP_IPHONE_67",
    "ipad-13": "APP_IPAD_PRO_3GEN_129",
}

# Le texte de la fiche. Ici et non dans un formulaire : il se relit en diff,
# il se corrige en pull request, et il ne se perd pas.
FICHE = {
    "subtitle": "Le cosmos hébreu restitué",
    "description": (
        "La Bible ONT est une restitution française du corpus hébreu et araméen "
        "antique, fondée sur l'ontologie hébraïque fonctionnelle.\n\n"
        "Le cosmos hébreu n'est pas une usine. C'est un Temple.\n\n"
        "TROIS NIVEAUX, JAMAIS CONFONDUS\n\n"
        "Une restitution ne peut pas tout dire dans la même ligne. L'ONT sépare "
        "ce que l'hébreu dit, ce qu'il portait implicitement pour son lecteur, "
        "et le mot original avec sa translittération. Chaque niveau s'éteint "
        "d'un geste, pour lire le corps seul.\n\n"
        "LES INTRADUISIBLES RESTENT DEBOUT\n\n"
        "Elohim, neshamah, kavod, ruach. Ces mots ne sont pas traduits : les "
        "rendre coûterait ce qu'ils portent. Chacun a sa fiche, et chaque fiche "
        "montre où le terme paraît dans le corpus.\n\n"
        "UN CHANTIER OUVERT\n\n"
        "Trois livres sur soixante-dix. Le compte est public, et il est tenu par "
        "le corpus lui-même. Une unité verrouillée a été relue et validée ; une "
        "unité qui ne l'est pas est un brouillon, et le dit.\n\n"
        "HORS LIGNE\n\n"
        "Le texte est dans l'app. Il se met à jour tout seul quand une "
        "correction paraît, et il se lit sans réseau."
    ),
    "keywords": "bible,hébreu,traduction,torah,araméen,exégèse,ONT,corpus,lexique",
    "supportUrl": "https://ontbible.com/fr/assistance",
    "marketingUrl": "https://ontbible.com",
}


def numero_du_projet() -> str:
    """La version publique, lue là où elle fait déjà foi.

    `CFBundleShortVersionString` d'`app/project.yml` est le numéro que porte le
    binaire ; c'est lui qu'App Store Connect doit trouver en face. L'écrire une
    seconde fois ici, c'est se garantir qu'un jour la fiche préparera une
    version que personne ne construit.
    """
    trouve = re.search(
        r'CFBundleShortVersionString:\s*"([^"]+)"', PROJET.read_text(encoding="utf8")
    )
    if not trouve:
        raise SystemExit(f"CFBundleShortVersionString introuvable dans {PROJET}")
    return trouve.group(1)


def version_a_remplir(c: Client, app: str) -> str:
    """La version en préparation — reprise si elle existe, créée sinon.

    Une version déjà en vente n'est plus modifiable. Tant que la suivante
    n'existe pas, la fiche n'a nulle part où se poser, et la chaîne s'arrêtait
    ici sur un message demandant d'aller cliquer dans l'interface web.
    `soumettre.py` avait déjà tranché dans l'autre sens pour la même raison.
    """
    toutes = c.get(f"apps/{app}/appStoreVersions", limit=20)["data"]
    for v in toutes:
        if v["attributes"]["appStoreState"] in MODIFIABLES:
            print(
                f"  version {v['attributes']['versionString']} reprise "
                f"({v['attributes']['appStoreState']})"
            )
            return v["id"]

    numero = numero_du_projet()
    cree = c.post(
        "appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": "IOS",
                    "versionString": numero,
                    "releaseType": "AFTER_APPROVAL",
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        },
    )
    print(f"  version {numero} créée")
    return cree["data"]["id"]


def televerser_captures(c: Client, version: str) -> None:
    """Les captures, réservées puis poussées puis validées.

    Apple ne prend pas un fichier d'un coup : on **réserve** une place en
    annonçant le nom et la taille, il rend une adresse et une méthode, on y
    pousse les octets, puis on **valide** avec l'empreinte MD5. Sans cette
    dernière étape, l'image reste en attente et n'apparaît nulle part — sans
    qu'aucune erreur ne le dise.

    ## Pourquoi on supprime avant d'envoyer

    Une version en préparation **hérite des captures de la précédente**. Créer
    un jeu pour un format qui en a déjà un ne le remplace pas : selon les cas
    Apple refuse, ou empile un second jeu et sert l'ancien. Le script partait
    du cas de la 1.0, où la fiche était vierge, et ne pouvait donc pas
    fonctionner deux fois — ce qui est précisément ce qu'on lui demande, les
    captures se refaisant à chaque changement visuel.
    """
    localisations = c.get(f"appStoreVersions/{version}/appStoreVersionLocalizations")
    loc = localisations["data"][0]["id"]

    existants = c.get(f"appStoreVersionLocalizations/{loc}/appScreenshotSets")["data"]

    for dossier, format_apple in FORMATS.items():
        images = sorted((CAPTURES / dossier).glob("*.png"))
        if not images:
            print(f"  {dossier} : aucune capture, sauté")
            continue

        for ancien in existants:
            if ancien["attributes"]["screenshotDisplayType"] == format_apple:
                c.delete(f"appScreenshotSets/{ancien['id']}")
                print(f"  {dossier} : ancien jeu supprimé")

        jeu = c.post(
            "appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": format_apple},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": loc,
                            }
                        }
                    },
                }
            },
        )["data"]["id"]

        for image in images:
            octets = image.read_bytes()
            reserve = c.post(
                "appScreenshots",
                {
                    "data": {
                        "type": "appScreenshots",
                        "attributes": {
                            "fileName": image.name,
                            "fileSize": len(octets),
                        },
                        "relationships": {
                            "appScreenshotSet": {
                                "data": {"type": "appScreenshotSets", "id": jeu}
                            }
                        },
                    }
                },
            )["data"]

            for morceau in reserve["attributes"]["uploadOperations"]:
                requests.request(
                    morceau["method"],
                    morceau["url"],
                    headers={h["name"]: h["value"] for h in morceau["requestHeaders"]},
                    data=octets[morceau["offset"] : morceau["offset"] + morceau["length"]],
                    timeout=120,
                ).raise_for_status()

            c.patch(
                f"appScreenshots/{reserve['id']}",
                {
                    "data": {
                        "type": "appScreenshots",
                        "id": reserve["id"],
                        "attributes": {
                            "uploaded": True,
                            "sourceFileChecksum": hashlib.md5(octets).hexdigest(),
                        },
                    }
                },
            )
            print(f"  {dossier}/{image.name} téléversée")


def main() -> None:
    arguments = argparse.ArgumentParser()
    arguments.add_argument("--captures", action="store_true", help="téléverser les captures")
    options = arguments.parse_args()

    c = Client()
    app = application(c)
    print(f"  app {app}")

    # Le texte, sur la localisation française de la version en préparation.
    version = version_a_remplir(c, app)

    loc = c.get(f"appStoreVersions/{version}/appStoreVersionLocalizations")["data"][0]
    c.patch(
        f"appStoreVersionLocalizations/{loc['id']}",
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": loc["id"],
                "attributes": {
                    k: v for k, v in FICHE.items() if k != "subtitle"
                },
            }
        },
    )
    print("  description, mots-clés et adresses posés")

    # Le sous-titre vit sur `appInfoLocalizations`, pas sur la version : il ne
    # change pas d'une version à l'autre.
    #
    # **On ne le pose que sur une fiche modifiable.** Le script prenait la
    # première venue à défaut d'en trouver une en préparation — c'est-à-dire
    # celle de la version *en vente*, qu'Apple verrouille. Il rendait alors
    # 409 « The field 'subtitle' can not be modified in the current state », et
    # mourait là : avant de téléverser les captures, qui sont pourtant la
    # raison d'être de l'appel. Une étape facultative ne doit pas emporter
    # celles qui la suivent.
    infos = c.get(f"apps/{app}/appInfos")["data"]
    modifiable = next(
        (i for i in infos if i["attributes"]["appStoreState"] in MODIFIABLES), None
    )
    if modifiable is None:
        print("  sous-titre : aucune fiche modifiable, sauté")
    else:
        info_loc = c.get(f"appInfos/{modifiable['id']}/appInfoLocalizations")["data"][0]
        c.patch(
            f"appInfoLocalizations/{info_loc['id']}",
            {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": info_loc["id"],
                    "attributes": {
                        "subtitle": FICHE["subtitle"],
                        "privacyPolicyUrl": "https://ontbible.com/fr/confidentialite",
                    },
                }
            },
        )
        print("  sous-titre et politique de confidentialité posés")

    # Les droits sur le contenu. La traduction est celle de l'auteur : l'app ne
    # montre aucun contenu de tiers.
    c.patch(
        f"apps/{app}",
        {
            "data": {
                "type": "apps",
                "id": app,
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"
                },
            }
        },
    )
    print("  droits sur le contenu déclarés")

    if options.captures:
        televerser_captures(c, version)

    print(
        "\n  Restent à faire à la main, l'API d'Apple ne les expose pas :\n"
        "    · les étiquettes de confidentialité (Trust & Safety → App Privacy)\n"
        "    · le statut de commerçant (Business → Trader Status)"
    )


if __name__ == "__main__":
    sys.exit(main())
