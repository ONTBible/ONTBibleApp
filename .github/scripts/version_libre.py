"""Le numéro public est-il encore disponible ?

## Le défaut, tel qu'il s'est produit trois fois

App Store Connect refuse un téléversement dont le `CFBundleShortVersionString`
est celui d'une version déjà **approuvée**. Le refus arrive au bout : la
compilation a tourné, l'archive est signée, les certificats sont posés — et
c'est l'envoi qui casse. Puis ça recommence à chaque fusion, tant que le numéro
n'a pas bougé.

Trois fois en quinze jours : 1.0.3 le 24 août 2026 (cinq livraisons mortes de
suite), 1.0.4 le 30 août, 1.0.5 le 8 septembre. L'approbation arrive sans
prévenir, rien dans le dépôt ne l'apprend, et `app/project.yml` portait le
constat écrit sans le contrôle qui va avec.

Ce script pose la question **avant** de dépenser, à qui connaît la réponse.

## Pourquoi App Store Connect et non les releases GitHub

Une release GitHub existe dès qu'une version atteint `app-store` — c'est-à-dire
dès la *soumission*, pas dès l'approbation. Une version soumise puis rejetée
accepte parfaitement un nouveau build sous le même numéro ; s'appuyer sur la
release bloquerait cette relance-là.

L'instrument aurait été exact, et il aurait répondu à une autre question que
celle qu'on pose. La question est « ce numéro est-il approuvé », et le seul qui
la connaisse est Apple.

## Ce qui bloque, et ce qui ne bloque pas

Bloquent les états **à partir de l'approbation** : le numéro y est acquis au
public, Apple n'en reprendra pas de build.

Ne bloquent pas les états où la version se retravaille encore — en préparation,
en attente de revue, en revue, rejetée. Y refuser un téléversement serait le
défaut inverse : empêcher exactement la correction qu'un rejet appelle.

## En cas de panne, on laisse passer

Une erreur de transport ou d'authentification n'apprend rien sur le numéro.
Arrêter la livraison là-dessus ferait de ce garde-fou une panne de plus, alors
qu'il n'existe que pour épargner une archive. Il avertit et rend la main.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc  # noqa: E402

# Les états où le numéro est acquis : approuvé, en attente de mise en vente, ou
# en vente. Le reste se retravaille, et doit pouvoir recevoir un build de plus.
ACQUIS = {
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_APP_STORE",
    "READY_FOR_SALE",
    "REPLACED_WITH_NEW_VERSION",
}


def version_du_projet(chemin: str) -> str:
    """La version publique, lue dans `app/project.yml`.

    **Sans analyseur YAML**, et sans dépendance de plus : la ligne cherchée est
    la première `CFBundleShortVersionString` du fichier, et c'est celle de la
    cible `ONT` — l'app iOS. Les deux autres cibles la suivent dans le fichier.

    **Sa limite, nommée pour qu'elle ne surprenne pas.** Le job macOS emploie
    donc le numéro d'`ONT` et le pose à Apple sur `MAC_OS`. Les trois cibles
    portent la même version aujourd'hui ; `publier-la-version.yml` documente
    lui-même qu'`ONTMac` peut diverger. Le jour où elle divergera, ce lecteur
    rendra un nombre exact à une autre question que celle qu'on pose — et il
    faudra ancrer la lecture sur la cible, `targets.ONTMac` pour le Mac.

    Pas fait maintenant : personne n'a besoin de cet ancrage tant que les
    numéros coïncident, et une machinerie posée « au cas où » se relit mal.
    """
    with open(chemin, encoding="utf-8") as f:
        for ligne in f:
            m = re.match(r'\s*CFBundleShortVersionString:\s*"([^"]+)"', ligne)
            if m:
                return m.group(1)
    raise SystemExit(f"Aucun CFBundleShortVersionString dans {chemin}.")


def verifier(client, app: str, version: str, plateforme: str) -> None:
    """Lève si le numéro est acquis, se tait sinon.

    Séparé de `main` pour être éprouvable : ce qui se mesure ici est le **choix
    de la branche** face à un état donné, et il ne demande ni réseau ni clé.
    C'est exactement ce que le faux client d'`epreuves.py` sait rendre.
    """
    versions = client.get(
        f"apps/{app}/appStoreVersions",
        **{
            "filter[versionString]": version,
            "filter[platform]": plateforme,
            "limit": 10,
        },
    )["data"]

    for v in versions:
        etat = v["attributes"].get("appStoreState")
        if etat in ACQUIS:
            raise SystemExit(
                f"\nLa version {version} est déjà acquise à l'App Store — état "
                f"« {etat} ».\n"
                "\n"
                "Apple refusera le téléversement, et le refus arriverait après la\n"
                "compilation et la signature de l'archive. On s'arrête avant.\n"
                "\n"
                "Le geste : monter `CFBundleShortVersionString` dans\n"
                "`app/project.yml` — les trois cibles —, puis relancer. Le numéro\n"
                "de build, lui, n'a pas ce problème : il est daté.\n"
            )
        print(f"  {version} existe en état « {etat} » — le numéro reste ouvert.")

    if not versions:
        print(f"  aucune version {version} chez Apple — le numéro est libre.")


def main() -> None:
    projet = os.environ.get("PROJET", "app/project.yml")
    plateforme = os.environ.get("PLATEFORME", "IOS")
    version = version_du_projet(projet)
    print(f"Version publique visée : {version} ({plateforme})")

    # `SystemExit` traverse — c'est le verdict, pas une panne. Tout le reste
    # est une panne, et une panne n'apprend rien sur le numéro : voir l'en-tête.
    try:
        client = asc.Client()
        app = asc.application(client)
        verifier(client, app, version, plateforme)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"::warning::Version non vérifiable auprès d'App Store Connect : {e}")


if __name__ == "__main__":
    main()
