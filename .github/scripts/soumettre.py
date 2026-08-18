#!/usr/bin/env python3

"""Soumet le build à la revue de l'App Store.

Appelé par `.github/workflows/livraison.yml`, sur `main` ou sur demande
explicite — les deux seules manières d'atteindre le public.

## Il crée la version quand la précédente est en vente

Une version `READY_FOR_SALE` ne se modifie plus. Tant que la suivante n'existe
pas, il n'y a rien où rattacher un build, et le script s'arrêtait là en
demandant d'aller la créer dans l'interface. Il la crée désormais lui-même, avec
le numéro que porte le binaire.

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

import os
import sys

from asc import API, Client, application, attendre_le_build, detailler

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

# « Nouveautés de cette version » — ce que le lecteur lit dans l'App Store avant
# de mettre à jour. Ici et non dans un formulaire, pour la même raison que la
# fiche : ça se relit en diff, et ça se corrige en pull request.
NOUVEAUTES = (
    "Des correctifs d'affichage et de lecture.\n"
    "\n"
    "LA GLOSE\n"
    "Sur les thèmes clairs, le commentaire entre crochets ne se détachait pas "
    "assez du texte traduit : on ne voyait plus où finissait la traduction et "
    "où commençait le commentaire. Les quatre thèmes visaient le même écart, "
    "alors qu'un même écart ne produit pas le même recul sur un fond clair et "
    "sur un fond sombre. La glose recule désormais franchement, sur les "
    "quatre.\n"
    "\n"
    "LE THÈME\n"
    "Changer de thème s'applique maintenant partout et tout de suite, sans "
    "rouvrir l'app — y compris dans la feuille de réglages, qui est justement "
    "l'endroit où l'on en change. La rangée « Thème » n'y reste plus écrite "
    "dans les couleurs de l'ancien, et le menu ne surligne plus une valeur "
    "pendant que la coche en désigne une autre.\n"
    "\n"
    "LES SÉLECTEURS\n"
    "Le segment retenu débordait de sa case et passait sous son voisin : "
    "« Intraduisibles » recouvrait « Vocabulaire fixé ». Les parts sont "
    "désormais mesurées et égales. Quand la place manque — aux grandes tailles "
    "de texte, surtout — le libellé retenu se lit toujours en entier, puisque "
    "c'est lui qui dit où l'on est ; seuls les autres se tronquent."
)

# Les états d'une version qu'on peut encore remplir et envoyer.
#
# `PREPARE_FOR_SUBMISSION` est celui d'une version qu'on remplit.
# `DEVELOPER_REJECTED` est celui d'une version dont **on** a annulé la
# soumission — pour changer de build, typiquement.
# `REJECTED` est celui d'une version qu'**Apple** a renvoyée. C'est le cas le
# plus utile, celui où l'on a quelque chose à corriger, et ne pas le reconnaître
# obligeait à repasser par l'interface.
MODIFIABLES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")


def numero_de_version(client, build: str) -> str:
    """La version publique que porte le binaire — `CFBundleShortVersionString`.

    Demandée à Apple plutôt que lue dans `project.yml` : c'est celle du build
    qu'on soumet, et non celle du dépôt au moment où le script tourne. Les deux
    divergent dès qu'une livraison est rejouée sur un commit plus ancien.
    """
    return client.get(f"builds/{build}/preReleaseVersion")["data"]["attributes"]["version"]


def creer_la_version(client, app: str, numero: str) -> str:
    """La version App Store, créée quand la précédente est déjà en vente.

    Une version `READY_FOR_SALE` n'est plus modifiable : tant que la suivante
    n'existe pas, aucun build ne peut être rattaché ni soumis. C'était jusqu'ici
    un passage obligé par l'interface web — et donc l'endroit où la chaîne
    s'arrêtait à chaque mise à jour, avec un message qui parlait d'une version
    « à créer et à remplir » sans dire que le remplissage, lui, est déjà écrit
    dans `fiche.py`.

    `AFTER_APPROVAL` reconduit ce que faisait la 1.0 : Apple met en vente dès
    qu'il approuve, sans qu'on ait à revenir cliquer.
    """
    cree = client.post("appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": numero,
                       "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    print(f"  version {numero} créée")
    return cree["data"]["id"]


def main() -> None:
    client = Client()
    numero = os.environ["BUILD"]

    app = application(client)

    build = attendre_le_build(client, app, numero)

    # Toutes les versions, et non les seules modifiables : savoir ce qui existe
    # à côté dit si celle qu'on soumet est la première de l'app, ce dont dépend
    # le champ « nouveautés » plus bas.
    #
    # Par la **relation** de l'app, et non par un filtre sur la collection :
    # `appStoreVersions?filter[app]=…` rend 403, quelle que soit la clé.
    toutes = client.get(f"apps/{app}/appStoreVersions", limit=20)["data"]
    modifiables = [v for v in toutes
                   if v["attributes"]["appStoreState"] in MODIFIABLES]

    if modifiables:
        version = modifiables[0]["id"]
        print(f"  version {modifiables[0]['attributes']['versionString']} reprise "
              f"({modifiables[0]['attributes']['appStoreState']})")
    else:
        # Aucune version n'attend : la précédente est en vente. On crée la
        # suivante avec le numéro que porte le binaire, plutôt que d'arrêter la
        # chaîne sur un message qui demande d'aller cliquer.
        version = creer_la_version(client, app, numero_de_version(client, build))

    # Est-ce la toute première version de l'app ? La question se pose sur les
    # **autres** versions, et non sur leur nombre : celle qu'on vient de créer
    # ne figure pas dans la liste lue plus haut.
    premiere = not [v for v in toutes if v["id"] != version]

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
    }

    # Les notes, elles, ne sont **jamais** remplacées.
    #
    # Apple avait renvoyé la 1.0 au titre de la Guideline 2.1 en demandant que
    # sept points soient répondus dans ce champ. La réponse y est, longue de
    # trois mille caractères, et c'est elle qui a fait approuver l'app. La
    # constante ci-dessus en dit dix lignes : l'écrire par-dessus effacerait le
    # travail d'une main pour y mettre moins.
    #
    # On ne la sème donc que dans un champ vide — ce qui reste utile, puisqu'une
    # version fraîchement créée n'hérite pas toujours de la fiche précédente.
    ancien = ((detail or {}).get("attributes") or {}).get("notes") or ""
    if ancien.strip():
        print(f"  notes de revue conservées ({len(ancien)} caractères)")
    else:
        contact["notes"] = NOTES
        print("  notes de revue semées")

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

    # « Nouveautés de cette version ».
    #
    # Obligatoire dès la deuxième version, et seulement à partir d'elle : Apple
    # refuse une mise à jour dont le champ est vide, et refuse aussi qu'une
    # première version en porte un. Le refus arrive à l'envoi, sous la forme
    # d'une erreur qui ne nomme pas le champ.
    #
    # Comme les notes de revue, il n'est jamais remplacé : ce qu'une main a
    # écrit vaut mieux que ce qu'une constante suppose.
    if not premiere:
        for loc in client.get(
                f"appStoreVersions/{version}/appStoreVersionLocalizations")["data"]:
            langue = loc["attributes"].get("locale")
            if (loc["attributes"].get("whatsNew") or "").strip():
                print(f"  nouveautés conservées en {langue}")
                continue
            client.patch(f"appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"],
                "attributes": {"whatsNew": NOUVEAUTES}}})
            print(f"  nouveautés posées en {langue}")

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
