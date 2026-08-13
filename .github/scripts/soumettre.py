#!/usr/bin/env python3

"""Soumet le build à la revue de l'App Store.

Appelé par `.github/workflows/testflight.yml`, uniquement sur une étiquette
`v*` ou sur demande explicite.

## Pourquoi ce script et pas fastlane

fastlane ferait ça très bien, et ajouterait Ruby, ses gemmes et son verrou de
dépendances pour une centaine de lignes d'API REST. Ce fichier n'a besoin que de
trois bibliothèques et il tient dans une seule lecture.

## Il attend qu'Apple ait fini

Un build téléversé n'est pas immédiatement soumettable : Apple le vérifie et
indexe ses symboles, ce qui prend de cinq à trente minutes. Tant que son état
est `PROCESSING`, toute soumission est refusée. On patiente ici plutôt que
d'échouer et de demander de relancer.
"""

import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.labibleont.ONT"


def jeton() -> str:
    """Le jeton JWT qu'attend App Store Connect.

    Vingt minutes de validité : Apple refuse au-delà, et il n'y a aucune raison
    d'aller au maximum autorisé.
    """
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
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {jeton()}"

    def get(self, chemin: str, **params) -> dict:
        r = self.session.get(f"{API}/{chemin}", params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    def post(self, chemin: str, corps: dict) -> dict:
        r = self.session.post(f"{API}/{chemin}", json=corps, timeout=30)
        if r.status_code >= 400:
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{r.text}")
        return r.json()


def main() -> None:
    client = Client()
    numero = os.environ["BUILD"]

    apps = client.get("apps", **{"filter[bundleId]": BUNDLE})["data"]
    if not apps:
        raise SystemExit(
            f"Aucune app pour {BUNDLE}. La fiche doit exister dans App Store "
            "Connect — c'est l'étape zéro, et elle se fait à la main."
        )
    app = apps[0]["id"]

    # Le build, attendu jusqu'à ce qu'Apple l'ait traité.
    build = None
    for essai in range(60):  # trente minutes, à trente secondes près
        builds = client.get(
            "builds",
            **{"filter[app]": app, "filter[version]": numero, "limit": 1},
        )["data"]
        if builds:
            etat = builds[0]["attributes"]["processingState"]
            print(f"  build {numero} : {etat}")
            if etat == "VALID":
                build = builds[0]["id"]
                break
            if etat in ("FAILED", "INVALID"):
                raise SystemExit(f"Apple a rejeté le build {numero} : {etat}")
        else:
            print(f"  build {numero} : pas encore reçu")
        time.sleep(30)

    if not build:
        raise SystemExit(
            f"Le build {numero} n'était pas prêt après trente minutes. "
            "Il n'est pas perdu : relancer ce workflow le reprendra."
        )

    # La version en préparation. Il n'y en a qu'une à la fois dans cet état ;
    # si elle n'existe pas, c'est qu'aucune version n'attend d'être remplie.
    versions = client.get(
        f"apps/{app}/appStoreVersions",
        **{"filter[appStoreState]": "PREPARE_FOR_SUBMISSION", "limit": 1},
    )["data"]
    if not versions:
        raise SystemExit(
            "Aucune version en préparation dans App Store Connect. Une version "
            "doit y être créée et remplie — description, captures, classement "
            "d'âge — avant qu'une soumission ait un sens."
        )
    version = versions[0]["id"]

    # Rattacher le build à la version, puis soumettre.
    client.session.patch(
        f"{API}/appStoreVersions/{version}/relationships/build",
        json={"data": {"type": "builds", "id": build}},
        timeout=30,
    ).raise_for_status()
    print(f"  build {numero} rattaché à la version")

    client.post(
        "appStoreVersionSubmissions",
        {
            "data": {
                "type": "appStoreVersionSubmissions",
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version}
                    }
                },
            }
        },
    )
    print("  soumis à la revue")


if __name__ == "__main__":
    sys.exit(main())
