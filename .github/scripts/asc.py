"""Ce que les livraisons partagent avec App Store Connect.

Deux scripts parlent à cette API — `beta.py` pour la bêta externe, et
`soumettre.py` pour la revue de l'App Store. Ils ont en commun l'authentification,
la lecture des erreurs d'Apple et l'attente du build. Recopier ces trois choses
dans les deux fichiers les ferait diverger à la première correction, et une
divergence sur la signature d'un jeton ne se voit qu'en production.
"""

import os
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


class Client:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {jeton()}"

    def get(self, chemin: str, **params) -> dict:
        r = self.session.get(f"{API}/{chemin}", params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    def post(
        self,
        chemin: str,
        corps: dict,
        tolerer: tuple[int, ...] = (),
        tolerer_si: tuple[str, ...] = (),
    ) -> dict:
        """`tolerer` nomme les codes d'échec qui ne sont pas des échecs.

        Apple rend 409 quand on redemande ce qu'il a déjà — une soumission de
        bêta pour un build qu'il a déjà vu, par exemple. Ce n'est pas une
        erreur : c'est l'état voulu, atteint plus tôt. Sans cette porte, une
        relance du workflow échouerait pour avoir réussi.

        `tolerer_si` fait la même chose, mais **sur le motif** : le code seul ne
        suffit pas toujours à distinguer une file d'attente d'une vraie
        malfaçon. Un 422 dit aussi bien « un autre build est déjà en revue »,
        qui se résout tout seul, que « il manque une information de test », qui
        ne se résout jamais. Tolérer le code entier masquerait la seconde.
        """
        r = self.session.post(f"{API}/{chemin}", json=corps, timeout=30)
        if r.status_code in tolerer:
            return {}
        if r.status_code >= 400:
            motif = detailler(r)
            if any(m in motif for m in tolerer_si):
                print(f"  toléré — {motif.strip()}")
                return {}
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{motif}")
        # Une relation créée rend 204 : appeler `.json()` dessus lèverait.
        return r.json() if r.content else {}

    def patch(self, chemin: str, corps: dict) -> dict:
        r = self.session.patch(f"{API}/{chemin}", json=corps, timeout=30)
        if r.status_code >= 400:
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{detailler(r)}")
        return r.json() if r.content else {}

    def delete(self, chemin: str) -> None:
        """404 est toléré : l'objet qu'on voulait absent l'est déjà."""
        r = self.session.delete(f"{API}/{chemin}", timeout=30)
        if r.status_code == 404:
            return
        if r.status_code >= 400:
            raise SystemExit(f"{r.status_code} sur {chemin} :\n{detailler(r)}")


def application(client: Client) -> str:
    """L'identifiant de l'app, depuis son bundle."""
    apps = client.get("apps", **{"filter[bundleId]": BUNDLE})["data"]
    if not apps:
        raise SystemExit(
            f"Aucune app pour {BUNDLE}. La fiche doit exister dans App Store "
            "Connect — c'est l'étape zéro, et elle se fait à la main."
        )
    return apps[0]["id"]


def attendre_le_build(
    client: Client, app: str, numero: str, plateforme: str = "IOS"
) -> str:
    """Le build, attendu jusqu'à ce qu'Apple l'ait traité.

    Le téléversement ne suffit pas : Apple le déchiffre, le valide et l'indexe,
    ce qui prend de cinq à trente minutes. Tant qu'il n'est pas `VALID`, on ne
    peut ni le rattacher à un groupe ni le soumettre.

    ## Pourquoi la plateforme est un filtre et non un détail

    L'app est en **achat universel** : `com.labibleont.ONT` est le même
    identifiant sur l'iPhone et sur le Mac, donc une seule fiche App Store
    Connect porte les builds des deux. Et le numéro de build est **daté à la
    minute** — `250831.1430`. Les deux livraisons partant du même push, elles
    tombent dans la même minute dès que les deux chaînes vont à la même vitesse.

    Sans ce filtre, `filter[version]` rendrait alors deux builds et `limit: 1`
    en choisirait un au hasard : on attendrait l'iPhone en croyant attendre le
    Mac, on rattacherait le mauvais au groupe, et rien ne le dirait — les deux
    réponses sont `VALID`.

    `IOS` ou `MAC_OS`, les valeurs d'Apple.
    """
    for _ in range(60):  # trente minutes, à trente secondes près
        builds = client.get(
            "builds",
            **{
                "filter[app]": app,
                "filter[version]": numero,
                "filter[preReleaseVersion.platform]": plateforme,
                "limit": 1,
            },
        )["data"]
        if builds:
            etat = builds[0]["attributes"]["processingState"]
            print(f"  build {numero} : {etat}")
            if etat == "VALID":
                return builds[0]["id"]
            if etat in ("FAILED", "INVALID"):
                raise SystemExit(f"Apple a rejeté le build {numero} : {etat}")
        else:
            print(f"  build {numero} : pas encore reçu")
        time.sleep(30)

    raise SystemExit(
        f"Le build {numero} n'était pas prêt après trente minutes. "
        "Il n'est pas perdu : relancer ce workflow le reprendra."
    )
