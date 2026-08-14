#!/usr/bin/env python3

"""Soumet le build à la revue de l'App Store.

Appelé par `.github/workflows/testflight.yml`, uniquement sur une étiquette
`v*` ou sur demande explicite.

## Pourquoi ce script et pas fastlane

fastlane ferait ça très bien, et ajouterait Ruby, ses gemmes et son verrou de
dépendances pour une centaine de lignes d'API REST. Ce fichier n'a besoin que de
trois bibliothèques et il tient dans une seule lecture.

## `reviewSubmissions`, et pas `appStoreVersionSubmissions`

Le second est l'ancien point d'entrée, celui d'avant que la revue puisse porter
plusieurs objets à la fois — une version, un événement, une expérimentation. Il
ne sait soumettre qu'une version, et Apple ne le développe plus.

Le nouveau se fait en trois temps, et c'est ce que fait ce script : on ouvre une
soumission, on y dépose ce qu'elle doit contenir, on l'envoie. La séparation a
une raison : entre le dépôt et l'envoi, Apple valide chaque objet et refuse
**celui** qui ne va pas, au lieu de rejeter le tout sans dire quoi.

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

# Ce que le relecteur doit savoir avant d'ouvrir l'app. Trois livres sur
# soixante-dix, et des unités marquées « brouillon » : sans cette note, un
# relecteur peut lire un chantier assumé comme une app inachevée — le motif de
# rejet 2.1 le plus courant.
NOTES = (
    "La Bible ONT est une restitution française du corpus hébreu et araméen "
    "antique, en cours de traduction. Trois livres sur soixante-dix sont "
    "publiés ; le sommaire montre les autres sans les rendre cliquables, et "
    "les unités non relues portent la mention « brouillon ». C'est délibéré, "
    "et non un contenu manquant.\n\n"
    "Aucun compte n'est nécessaire : l'app se lit entièrement sans se "
    "connecter. Le compte, facultatif, ne sert qu'à synchroniser notes et "
    "signets entre appareils.\n\n"
    "Le texte est téléchargé depuis ontbible.com après l'installation, pour "
    "qu'une correction de traduction atteigne les lecteurs sans passer par une "
    "mise à jour. L'app fonctionne hors ligne avec le corpus embarqué."
)


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
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{detailler(r)}")
        return r.json()

    def patch(self, chemin: str, corps: dict) -> dict:
        r = self.session.patch(f"{API}/{chemin}", json=corps, timeout=30)
        if r.status_code >= 400:
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{detailler(r)}")
        return r.json() if r.content else {}


def detailler(reponse) -> str:
    """Les erreurs d'Apple, lisibles.

    Elles arrivent en JSON et portent le champ fautif dans `source.pointer` —
    la seule information qui dise quoi corriger. Rendre `r.text` brut oblige à
    le déchiffrer à l'œil dans un journal de CI.
    """
    try:
        erreurs = reponse.json().get("errors", [])
    except ValueError:
        return reponse.text
    lignes = []
    for e in erreurs:
        champ = (e.get("source") or {}).get("pointer", "")
        lignes.append(f"  · {e.get('title')} — {e.get('detail')}"
                      + (f"  [{champ}]" if champ else ""))
    return "\n".join(lignes) or reponse.text


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
    # Deux états valent « prête à soumettre ».
    #
    # `PREPARE_FOR_SUBMISSION` est celui d'une version qu'on remplit.
    # `DEVELOPER_REJECTED` est celui d'une version dont **on** a annulé la
    # soumission — pour changer de build, typiquement. C'est exactement la
    # version qu'on veut resoumettre, et ne pas la reconnaître obligeait à
    # repasser par l'interface.
    versions = client.get(
        f"apps/{app}/appStoreVersions",
        **{
            "filter[appStoreState]": "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED",
            "limit": 1,
        },
    )["data"]
    if not versions:
        raise SystemExit(
            "Aucune version en préparation dans App Store Connect. Une version "
            "doit y être créée et remplie — description, captures, classement "
            "d'âge — avant qu'une soumission ait un sens."
        )
    version = versions[0]["id"]

    # Les informations de revue — le contact qu'Apple appelle si le relecteur
    # bloque. Sans elles, la soumission est refusée par un 409 qui ne nomme pas
    # ce qui manque : « This resource cannot be reviewed ».
    #
    # Elles vivent sur la **version**, donc elles sont à reposer à chaque
    # nouvelle version. Ce script les écrit plutôt que de supposer qu'on y a
    # pensé dans l'interface.
    detail = client.get(f"appStoreVersions/{version}/appStoreReviewDetail")["data"]
    contact = {
        "contactFirstName": os.environ.get("ASC_CONTACT_PRENOM", "Gloire"),
        "contactLastName": os.environ.get("ASC_CONTACT_NOM", "Bikouta"),
        "contactEmail": os.environ["ASC_CONTACT_EMAIL"],
        # Format international obligatoire — « +33 6 … ». Apple refuse le reste.
        "contactPhone": os.environ["ASC_CONTACT_TELEPHONE"],
        # L'app se lit entièrement sans compte : le relecteur n'a besoin de rien.
        "demoAccountRequired": False,
        "notes": NOTES,
    }
    if detail:
        client.patch(f"appStoreReviewDetails/{detail['id']}",
                     {"data": {"type": "appStoreReviewDetails",
                               "id": detail["id"], "attributes": contact}})
        print("  informations de revue mises à jour")
    else:
        client.post("appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": contact,
            "relationships": {"appStoreVersion": {
                "data": {"type": "appStoreVersions", "id": version}}}}})
        print("  informations de revue créées")

    # Rattacher le build à la version.
    r = client.session.patch(
        f"{API}/appStoreVersions/{version}/relationships/build",
        json={"data": {"type": "builds", "id": build}},
        timeout=30,
    )
    if r.status_code >= 400:
        raise SystemExit(f"rattachement refusé :\n{detailler(r)}")
    print(f"  build {numero} rattaché à la version")

    # ── La soumission, en trois temps ────────────────────────────────────────

    # Une soumission déjà ouverte est **réutilisée**. En ouvrir une seconde ne
    # marche pas — Apple n'en accepte qu'une en cours par app — et la première
    # resterait là, vide, à faire échouer toutes les suivantes.
    ouvertes = [
        s for s in client.get("reviewSubmissions",
                              **{"filter[app]": app, "limit": 10})["data"]
        if s["attributes"]["state"] in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")
    ]
    if ouvertes:
        soumission = ouvertes[0]["id"]
        print("  soumission déjà ouverte, reprise")
    else:
        soumission = client.post("reviewSubmissions", {"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]["id"]
        print("  soumission ouverte")

    deja = client.get(f"reviewSubmissions/{soumission}/items")["data"]
    if not any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == version
               for i in deja):
        client.post("reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": soumission}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version}}}}})
        print("  version déposée dans la soumission")

    etat = client.patch(f"reviewSubmissions/{soumission}",
                        {"data": {"type": "reviewSubmissions", "id": soumission,
                                  "attributes": {"submitted": True}}})
    print("  envoyé à Apple —", etat["data"]["attributes"]["state"])


if __name__ == "__main__":
    sys.exit(main())
