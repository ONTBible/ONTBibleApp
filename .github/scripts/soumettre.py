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
import pathlib
import sys

from asc import API, Client, application, attendre_le_build, detailler

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts"))
from compte_du_corpus import phrase  # noqa: E402

# Ce que le relecteur doit savoir avant d'ouvrir l'app. Le compte des livres
# se lit dans le corpus, et des unités marquées « brouillon » : sans cette note, un
# relecteur peut lire un chantier assumé comme une app inachevée — le motif de
# rejet 2.1 le plus courant.
NOTES = (
    "La Bible ONT est une restitution française du corpus hébreu et araméen "
    f"antique, en cours de traduction. {phrase()} sont "
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
    "Le renvoi biblique s'ouvre, et le verset hébreu se touche mot à mot.\n"
    "\n"
    "LE RENVOI BIBLIQUE\n"
    "Une référence citée au fil du texte — « Bereshit 1:3 » — était écrite "
    "comme du texte ordinaire : on la lisait sans pouvoir y aller. Elle se "
    "détache maintenant en ambre, soulignée de pointillés, et s'ouvre sur le "
    "verset qu'elle nomme, qui arrive sélectionné. Le bouton de retour ramène "
    "au chapitre et à l'endroit exact qu'on lisait. Quand le livre visé n'est "
    "pas encore traduit, l'app le dit au lieu de ne rien faire.\n"
    "\n"
    "LE VERSET D'ORIGINE\n"
    "Un appui long sur un verset ouvre sa source hébraïque. Le texte hébreu "
    "s'affiche en haut, chaque mot portant sa translittération dessous, et "
    "toucher un mot montre ce qu'il veut dire. On balaie pour passer au verset "
    "suivant, ou d'un mot à l'autre ; la fiche s'agrandit d'un bouton et "
    "reprend sa taille du même geste.\n"
    "\n"
    "POURQUOI C'EST ANNONCÉ MAINTENANT\n"
    "Ces deux nouveautés étaient déjà dans la version précédente : ses notes "
    "ne les mentionnaient pas, et décrivaient des correctifs d'affichage "
    "arrivés avant elles. Le texte n'avait pas suivi le code. Si vous venez "
    "de la 1.0.6, vous les avez donc déjà — c'est leur description qui "
    "manquait.\n"
    "\n"
    "ET SOUS LE CAPOT\n"
    "Les mises à jour du corpus et des langues sources s'installent "
    "entièrement ou pas du tout : plus de mélange possible entre deux "
    "générations. Et quand l'app refuse une mise à jour, elle dit désormais "
    "laquelle des raisons l'a fait refuser, au lieu de se taire."
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


def creer_la_version(client, app: str, numero: str, plateforme: str) -> str:
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
        "attributes": {"platform": plateforme, "versionString": numero,
                       "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    print(f"  version {numero} créée")
    return cree["data"]["id"]


def compter_les_captures(client, version: str) -> int | None:
    """Combien de captures la fiche de cette version porte-t-elle ?

    `None` quand la question n'a pas pu être posée — panne de transport,
    permission manquante. Ce n'est pas zéro : **ne rien trouver n'est pas
    trouver zéro**, et la doctrine du dépôt est de laisser passer sur une
    non-réponse plutôt que de bloquer une soumission valide.

    Extraite de `main` pour être éprouvable. Une garde qu'on ne peut pas
    retourner contre elle-même ne dit pas si elle sait refuser.
    """
    try:
        total = 0
        for loc in client.get(
                f"appStoreVersions/{version}/appStoreVersionLocalizations")["data"]:
            for jeu in client.get(
                    f"appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
                total += len(
                    client.get(f"appScreenshotSets/{jeu['id']}/appScreenshots")["data"])
        return total
    except Exception:  # noqa: BLE001 — volontaire, voir ci-dessus
        return None


def main() -> None:
    client = Client()
    numero = os.environ["BUILD"]

    app = application(client)

    plateforme = os.environ.get("PLATEFORME", "IOS")
    build = attendre_le_build(client, app, numero, plateforme)

    # Toutes les versions, et non les seules modifiables : savoir ce qui existe
    # à côté dit si celle qu'on soumet est la première de l'app, ce dont dépend
    # le champ « nouveautés » plus bas.
    #
    # Par la **relation** de l'app, et non par un filtre sur la collection :
    # `appStoreVersions?filter[app]=…` rend 403, quelle que soit la clé.
    #
    # `limit` relevé et la plateforme retenue depuis que la fiche en porte deux
    # — l'achat universel range les versions de l'iPhone et du Mac dans la
    # **même** collection. Le 31 août 2026, l'ajout de la plateforme macOS a
    # créé une version « 1.0 » en `PREPARE_FOR_SUBMISSION`, c'est-à-dire
    # modifiable, pendant que l'iOS 1.0.4 était `READY_FOR_SALE` et ne l'était
    # plus. `modifiables[0]` aurait donc rendu **la version du Mac** à une
    # livraison iPhone, qui y aurait écrit ses informations de revue et
    # rattaché son binaire.
    #
    # Le filtre est écrit « garder ce qui ne contredit pas » et non « garder ce
    # qui correspond » : si Apple cessait un jour de rendre `platform`, la
    # seconde forme viderait la liste et la chaîne créerait une version de plus
    # à chaque passage.
    toutes = [
        v for v in client.get(f"apps/{app}/appStoreVersions", limit=50)["data"]
        if v["attributes"].get("platform", plateforme) == plateforme
    ]
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
        version = creer_la_version(
            client, app, numero_de_version(client, build), plateforme)

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

    # ── Les captures, avant de soumettre ─────────────────────────────────────
    #
    # **Apple refuse une version sans captures, et le refus arrive au bout.**
    # C'est la même forme que le numéro déjà approuvé, que `version_libre.py`
    # ferme en amont : tout a tourné, et c'est le dernier appel qui casse. Puis
    # ça recommence à chaque fusion tant que la fiche n'a pas été remplie.
    #
    # Le cas n'était pas théorique. Jusqu'au 12 septembre 2026, ce script ne
    # soumettait qu'iOS, dont les captures étaient posées depuis longtemps.
    # L'ajout de macOS à la matrice ouvre un chemin où la plateforme est neuve
    # et sa fiche peut être vide — et seule la revue le dirait.
    #
    # `fiche.py --captures` les téléverse, mais il ne tourne **pas**
    # automatiquement : `fiche.yml` est un `workflow_dispatch`. Rien ne garantit
    # donc qu'il ait tourné pour cette plateforme, et c'est exactement pourquoi
    # la question se pose ici.
    #
    # **En cas de panne, on laisse passer** — doctrine du dépôt. Une erreur de
    # transport n'apprend rien sur les captures, et refuser sur une
    # non-réponse bloquerait une soumission parfaitement valide.
    captures = compter_les_captures(client, version)
    if captures is None:
        print("  captures : non vérifiables — on laisse passer")
    elif captures == 0:
        print(
            f"  ARRÊT : aucune capture dans la fiche {plateforme}.\n"
            "  Apple refuserait la revue, et le refus arriverait après\n"
            "  la compilation, la signature et le téléversement.\n"
            "\n"
            "  Le remède, une fois :\n"
            "      gh workflow run fiche.yml -f captures=true\n"
            "\n"
            "  Les captures sont dans le dépôt — `app/Captures/` — et\n"
            "  `fiche.py` sait les poser. Il ne tourne pas tout seul.")
        raise SystemExit(1)
    else:
        print(f"  captures : {captures} dans la fiche {plateforme}")

    # ── La soumission, en trois temps ────────────────────────────────────────

    # Une soumission déjà ouverte est **réutilisée**. En ouvrir une seconde ne
    # marche pas — Apple n'en accepte qu'une en cours par app — et la première
    # resterait là, vide, à faire échouer toutes les suivantes.
    # Par plateforme, pour la même raison que les versions ci-dessus : « une
    # seule soumission en cours » se compte par plateforme, et reprendre celle
    # du Mac pour y déposer une version de l'iPhone mélangerait les deux.
    ouvertes = [
        s for s in client.get("reviewSubmissions",
                              **{"filter[app]": app, "limit": 20})["data"]
        if s["attributes"]["state"] in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")
        and s["attributes"].get("platform", plateforme) == plateforme
    ]
    if ouvertes:
        soumission = ouvertes[0]["id"]
        print("  soumission déjà ouverte, reprise")
    else:
        soumission = client.post("reviewSubmissions", {"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": plateforme},
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
