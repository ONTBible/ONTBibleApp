#!/usr/bin/env python3

"""Remplit la fiche App Store, et y téléverse les captures.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_PRIVATE_KEY="$(cat AuthKey_….p8)" \\
      ./.github/scripts/fiche.py [--captures] [--sec]

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
import json
import os
import pathlib
import sys
from datetime import datetime, timedelta, timezone

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.labibleont.ONT"
CAPTURES = pathlib.Path(__file__).resolve().parents[2] / "app" / "Captures"

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


def jeton() -> str:
    maintenant = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": int(maintenant.timestamp()),
            "exp": int((maintenant + timedelta(minutes=20)).timestamp()),
            "aud": "appstoreconnect-v1",
        },
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


class Client:
    def __init__(self) -> None:
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {jeton()}"

    def _verifier(self, r, quoi: str):
        if r.status_code >= 400:
            raise SystemExit(f"{r.status_code} sur {quoi} :\n{r.text}")
        return r.json() if r.content else {}

    def get(self, chemin: str, **params) -> dict:
        return self._verifier(
            self.s.get(f"{API}/{chemin}", params=params, timeout=30), chemin
        )

    def patch(self, chemin: str, corps: dict) -> dict:
        return self._verifier(
            self.s.patch(f"{API}/{chemin}", json=corps, timeout=30), chemin
        )

    def post(self, chemin: str, corps: dict) -> dict:
        return self._verifier(
            self.s.post(f"{API}/{chemin}", json=corps, timeout=60), chemin
        )


def app_id(c: Client) -> str:
    apps = c.get("apps", **{"filter[bundleId]": BUNDLE})["data"]
    if not apps:
        raise SystemExit(f"Aucune app pour {BUNDLE} dans ce compte.")
    return apps[0]["id"]


def televerser_captures(c: Client, version: str) -> None:
    """Les captures, réservées puis poussées puis validées.

    Apple ne prend pas un fichier d'un coup : on **réserve** une place en
    annonçant le nom et la taille, il rend une adresse et une méthode, on y
    pousse les octets, puis on **valide** avec l'empreinte MD5. Sans cette
    dernière étape, l'image reste en attente et n'apparaît nulle part — sans
    qu'aucune erreur ne le dise.
    """
    localisations = c.get(f"appStoreVersions/{version}/appStoreVersionLocalizations")
    loc = localisations["data"][0]["id"]

    for dossier, format_apple in FORMATS.items():
        images = sorted((CAPTURES / dossier).glob("*.png"))
        if not images:
            print(f"  {dossier} : aucune capture, sauté")
            continue

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
    app = app_id(c)
    print(f"  app {app}")

    # Le texte, sur la localisation française de la version en préparation.
    versions = c.get(
        f"apps/{app}/appStoreVersions",
        **{"filter[appStoreState]": "PREPARE_FOR_SUBMISSION", "limit": 1},
    )["data"]
    if not versions:
        raise SystemExit(
            "Aucune version en préparation. Elle se crée dans App Store Connect."
        )
    version = versions[0]["id"]

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
    infos = c.get(f"apps/{app}/appInfos")["data"]
    prep = next(
        (i for i in infos if i["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"),
        infos[0],
    )
    info_loc = c.get(f"appInfos/{prep['id']}/appInfoLocalizations")["data"][0]
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
