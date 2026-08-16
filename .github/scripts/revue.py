"""Où en sont nos soumissions, chez Apple.

Deux revues coexistent et se confondent facilement :

* la **revue de bêta**, qui ouvre un build aux testeurs externes ;
* la **revue de l'App Store**, qui décide de la publication.

Elles ont leurs états, leurs délais et leurs refus propres. Ce script les lit
toutes les deux, sans rien modifier, plus la fiche qui les accompagne.
"""

import sys

from asc import Client, application


def fiche(client: Client, app: str) -> None:
    details = client.get(
        "betaAppReviewDetails", **{"filter[app]": app, "limit": 1}
    )["data"]
    if not details:
        print("  aucune fiche de revue de bêta")
        return
    a = details[0]["attributes"]
    compte = a.get("demoAccountRequired")
    contact = " ".join(
        x for x in [(a.get("contactFirstName") or ""), (a.get("contactLastName") or "")] if x
    ).strip()
    print("\n═══ La fiche de revue de bêta ═══\n")
    print(f"  compte de démonstration requis : {'OUI' if compte else 'non'}")
    print(f"  contact                        : {contact or '— vide —'}")
    print(f"  courriel                       : {(a.get('contactEmail') or '').strip() or '— vide —'}")
    print(f"  téléphone                      : {(a.get('contactPhone') or '').strip() or '— vide —'}")
    print(f"  consignes de test              : {len((a.get('betaAppReviewNotes') or '').strip())} caractère(s)")


def revues_de_beta(client: Client, app: str) -> None:
    """Les soumissions de bêta, du plus récent au plus ancien."""
    builds = client.get(
        "builds",
        **{"filter[app]": app, "limit": 8, "sort": "-uploadedDate",
           "include": "betaAppReviewSubmission"},
    )
    inclus = {o["id"]: o for o in builds.get("included", [])}
    print("\n═══ Les builds, et leur revue de bêta ═══\n")
    for b in builds["data"]:
        att = b["attributes"]
        lien = (b.get("relationships", {}).get("betaAppReviewSubmission", {}) or {}).get("data")
        etat = "—"
        if lien and lien["id"] in inclus:
            etat = inclus[lien["id"]]["attributes"].get("betaReviewState", "?")
        expire = " (expiré)" if att.get("expired") else ""
        print(f"  {att.get('version'):>14}  {att.get('processingState'):<10}  "
              f"revue de bêta : {etat}{expire}")


def revue_de_l_app_store(client: Client, app: str) -> None:
    """Les versions App Store et leur état de revue."""
    # Par la **relation** de l'app, et non par un filtre sur la collection :
    # `appStoreVersions?filter[app]=…` rend 403, quelle que soit la clé.
    versions = client.get(
        f"apps/{app}/appStoreVersions",
        **{"limit": 5, "include": "build"},
    )
    inclus = {o["id"]: o for o in versions.get("included", [])}
    print("\n═══ Les versions App Store ═══\n")
    if not versions["data"]:
        print("  aucune version")
    for v in versions["data"]:
        a = v["attributes"]
        lien = (v.get("relationships", {}).get("build", {}) or {}).get("data")
        build = inclus.get(lien["id"], {}).get("attributes", {}).get("version") if lien else None
        print(f"  {a.get('versionString'):>8}  {a.get('appStoreState'):<28}  "
              f"build {build or '—'}  ({a.get('platform')})")

    # La fiche que le relecteur d'Apple a sous les yeux.
    #
    # À ne pas confondre avec `betaAppReviewDetails`, qui ne concerne que la
    # bêta. C'est **celle-ci** que la Guideline 2.1 demande de remplir : le
    # champ « Notes » y répond aux questions sur les appareils testés, le
    # public visé, les services externes.
    for v in versions["data"]:
        try:
            d = client.get(f"appStoreVersions/{v['id']}/appStoreReviewDetail")["data"]
        except Exception as souci:
            print(f"\n  fiche de revue App Store illisible — {souci}")
            continue
        a = d["attributes"]
        notes = (a.get("notes") or "").strip()
        print(f"\n═══ La fiche de revue App Store — version {v['attributes'].get('versionString')} ═══\n")
        print(f"  compte de démonstration requis : {'OUI' if a.get('demoAccountRequired') else 'non'}")
        print(f"  contact  : {(a.get('contactFirstName') or '').strip()} {(a.get('contactLastName') or '').strip()}")
        print(f"  courriel : {(a.get('contactEmail') or '').strip() or '— vide —'}")
        print(f"  notes    : {len(notes)} caractère(s)")
        for ligne in notes.splitlines():
            print(f"    │ {ligne}")

        # Le build que le relecteur ouvrira, et sa date. Une version peut
        # rester attachée à un build ancien pendant qu'on en livre dix autres —
        # et c'est ce build-là, pas le dernier, qu'Apple juge.
        lien = (v.get("relationships", {}).get("build", {}) or {}).get("data")
        if lien:
            b = client.get(f"builds/{lien['id']}")["data"]["attributes"]
            print(f"\n  ⚠ build jugé : {b.get('version')} — téléversé le {b.get('uploadedDate')}")

    # La soumission de revue proprement dite — ce qu'on voit dans « App Review ».
    try:
        soumissions = client.get(
            "reviewSubmissions",
            **{"filter[app]": app, "filter[platform]": "IOS", "limit": 5},
        )["data"]
    except Exception as souci:  # une lecture qui échoue ne doit pas cacher le reste
        print(f"  lecture impossible — {souci}")
        return
    print("\n═══ Les soumissions à la revue ═══\n")
    if not soumissions:
        print("  aucune soumission")
    for s in soumissions:
        a = s["attributes"]
        print(f"  état : {a.get('state'):<24} soumise : {a.get('submittedDate') or '—'}")
        # Ce que la soumission portait, et l'état de chaque pièce. Le **motif**
        # du refus, lui, n'est pas dans l'API : il vit dans le Centre de
        # résolution d'App Store Connect, et seul un humain connecté le lit.
        try:
            pieces = client.get(f"reviewSubmissions/{s['id']}/items", limit=10)["data"]
        except Exception as souci:
            print(f"     pièces illisibles — {souci}")
            continue
        for piece in pieces:
            p = piece["attributes"]
            quoi = [k for k, v in (piece.get("relationships") or {}).items()
                    if (v or {}).get("data")]
            print(f"     · {p.get('state', '?'):<22} {', '.join(quoi) or '—'}"
                  + (f"  résolu : {p.get('resolved')}" if p.get("resolved") is not None else ""))


def main() -> int:
    client = Client()
    app = application(client)
    fiche(client, app)
    revues_de_beta(client, app)
    revue_de_l_app_store(client, app)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
