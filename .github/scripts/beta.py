"""Livre le build au groupe de bêta **externe**, et le soumet à sa revue.

## Ce que le téléversement ne fait pas

Envoyer un build à App Store Connect le rend disponible aux testeurs
**internes**, et à eux seuls : ils reçoivent tout nouveau build sans rien
demander. Un groupe **externe** — celui dont on partage le lien public — ne
reçoit rien tant que deux gestes n'ont pas été faits :

1. le build lui est **explicitement rattaché** ;
2. il passe la **revue de bêta** d'Apple.

C'est pour ça qu'un « No Compatible Build » s'affiche sur un groupe externe
alors que les builds sont bien montés. Ce script fait ces deux gestes.

## La revue de bêta n'a lieu qu'une fois par version

Apple la demande pour le premier build d'un numéro de version, puis laisse
passer les suivants. Redemander une revue déjà faite rend un 409 — que l'on
tolère, parce que ce n'est pas un échec mais un état déjà atteint.
"""

import os
import sys

from asc import Client, application, attendre_le_build

# Ce que les testeurs lisent dans TestFlight avant d'installer. Le sujet du
# dernier commit y suffit : les messages de ce dépôt disent ce qui change et
# pourquoi.
NOTES_PAR_DEFAUT = "Nouvelle version de développement."


def main() -> None:
    client = Client()
    numero = os.environ["BUILD"]
    nom_du_groupe = os.environ.get("GROUPE_BETA", "Beta")
    notes = (os.environ.get("NOTES_BETA") or "").strip() or NOTES_PAR_DEFAUT

    app = application(client)
    build = attendre_le_build(client, app, numero)

    # ── Le groupe ────────────────────────────────────────────────────────────
    #
    # Cherché par son nom plutôt que par un identifiant en dur : un identifiant
    # dans un fichier de CI est une donnée qui ne se relit pas, et qui devient
    # fausse le jour où le groupe est recréé.
    groupes = client.get("betaGroups", **{"filter[app]": app, "limit": 200})["data"]
    groupe = next(
        (g for g in groupes if g["attributes"].get("name") == nom_du_groupe), None
    )
    if groupe is None:
        connus = ", ".join(g["attributes"].get("name", "?") for g in groupes) or "aucun"
        raise SystemExit(
            f"Aucun groupe nommé « {nom_du_groupe} ». Groupes existants : {connus}.\n"
            "Le groupe se crée à la main dans App Store Connect — c'est là qu'on "
            "décide s'il est public et qui peut s'y inscrire."
        )
    externe = groupe["attributes"].get("isInternalGroup") is False
    print(f"  groupe « {nom_du_groupe} » trouvé ({'externe' if externe else 'interne'})")

    # ── Ce que les testeurs liront ───────────────────────────────────────────
    #
    # Posé **avant** le rattachement : un testeur peut recevoir la notification
    # dans la seconde qui suit, et un « Nouvelle version » vide ne lui apprend
    # rien.
    localisations = client.get(
        "betaBuildLocalizations", **{"filter[build]": build}
    )["data"]
    if localisations:
        for locale in localisations:
            client.patch(
                f"betaBuildLocalizations/{locale['id']}",
                {"data": {"type": "betaBuildLocalizations", "id": locale["id"],
                          "attributes": {"whatsNew": notes}}},
            )
        print(f"  notes de test posées ({len(localisations)} langue(s))")
    else:
        client.post("betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "fr-FR", "whatsNew": notes},
            "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
        print("  notes de test créées (fr-FR)")

    # ── Le rattachement ──────────────────────────────────────────────────────
    #
    # 409 toléré : le build est déjà dans le groupe, ce qui est le but.
    client.post(
        f"betaGroups/{groupe['id']}/relationships/builds",
        {"data": [{"type": "builds", "id": build}]},
        tolerer=(409,),
    )
    print(f"  build {numero} rattaché à « {nom_du_groupe} »")

    if not externe:
        print("  groupe interne : aucune revue de bêta à demander")
        return

    # ── La revue de bêta ─────────────────────────────────────────────────────
    deja = client.get(
        "betaAppReviewSubmissions", **{"filter[build]": build, "limit": 1}
    )["data"]
    if deja:
        print("  revue de bêta déjà demandée —", deja[0]["attributes"].get("betaReviewState"))
        return

    reponse = client.post(
        "betaAppReviewSubmissions",
        {"data": {"type": "betaAppReviewSubmissions",
                  "relationships": {"build": {"data": {"type": "builds", "id": build}}}}},
        # 409 : Apple juge la revue inutile — le numéro de version a déjà été
        # revu. Le build partira quand même aux testeurs.
        tolerer=(409,),
    )
    etat = (reponse.get("data", {}).get("attributes") or {}).get("betaReviewState")
    print("  revue de bêta demandée —", etat or "déjà couverte par la version")


if __name__ == "__main__":
    sys.exit(main())
