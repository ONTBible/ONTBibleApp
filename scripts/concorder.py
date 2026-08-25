#!/usr/bin/env python3
"""Éprouve que les quatre `SYNCHRONISATION.md` disent la même chose.

    ./scripts/concorder.py                          dit ce qui diverge
    ./scripts/concorder.py --aligner-la-racine App  recopie depuis un dépôt

Rend **1** dès qu'une copie s'écarte des autres, pour qu'un enchaînement
s'arrête dessus.

## Pourquoi cet outil existe

Le 25 août 2026, toute la section « `git worktree` » a disparu de l'app. Elle
n'avait pas été supprimée : trois entrées de journal avaient été écrites dans la
copie de **la racine**, puis recopiées vers les trois dépôts.

Or la racine n'est pas un dépôt. Aucun `pull` ne l'atteint, aucune fusion ne la
corrige — elle dérive en silence. La recopie n'a donc rien perdu : elle a
**imposé un état périmé**.

La dérive a tenu deux jours sans que personne ne la voie, et trois règles
écrites ne l'ont pas empêchée. Une quatrième n'y ferait rien : ce qu'il manquait
n'était pas une consigne mais un **contrôle** — quelque chose qui ne peut pas
oublier de regarder.

## Ce qu'il compare, et pourquoi pas des empreintes

Une empreinte dit « ça diffère » et se tait sur le reste. Ce qu'on veut savoir
est **quelle copie manque de quoi** : c'est ce qui distingue « le vault est en
retard de trois entrées » de « quelqu'un a effacé une section ».

On compare donc les **titres** — les sections `##`/`###` et les entrées de
journal — parce que c'est l'unité à laquelle ce document s'écrit. Deux copies
qui portent les mêmes titres mais un paragraphe différent passeraient ; c'est
assumé, l'incident qu'on traite fait disparaître des sections entières.

## Ce qu'il lit

L'état **publié** de chaque dépôt — `origin/dev` pour l'app, `origin/main` pour
le vault et le site — et non l'arbre de travail, qui peut être sur une branche
en cours. C'est ce qui est publié qui fait foi.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

RACINE = Path.home() / "ONTBible"

# Le dépôt, et la branche où son exemplaire fait foi.
DEPOTS = {
    "App": ("ONTBibleApp", "dev"),
    "Translation": ("ONTBibleTranslation", "main"),
    "Webapp": ("ONTBibleWebapp", "main"),
}

FICHIER = "SYNCHRONISATION.md"


def publie(depot: str, branche: str) -> str | None:
    """Le fichier tel qu'il est publié, pas tel qu'il est sur le disque."""
    chemin = RACINE / depot
    if not (chemin / ".git").exists():
        return None
    subprocess.run(
        ["git", "-C", str(chemin), "fetch", "-q", "origin", branche],
        capture_output=True,
    )
    fait = subprocess.run(
        ["git", "-C", str(chemin), "show", f"origin/{branche}:{FICHIER}"],
        capture_output=True,
        text=True,
    )
    return fait.stdout if fait.returncode == 0 else None


def titres(texte: str) -> list[str]:
    """Les sections et les entrées de journal, dans l'ordre du fichier."""
    return [
        ligne.strip()
        for ligne in texte.splitlines()
        if re.match(r"^#{2,3} ", ligne)
    ]


def main() -> int:
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument(
        "--aligner-la-racine",
        metavar="DÉPÔT",
        choices=list(DEPOTS),
        help="recopie l'exemplaire publié d'un dépôt vers ~/ONTBible/",
    )
    options = arguments.parse_args()

    copies: dict[str, str] = {}
    for nom, (depot, branche) in DEPOTS.items():
        texte = publie(depot, branche)
        if texte is None:
            print(f"⚠  {nom} : dépôt introuvable ou {FICHIER} absent de origin/{branche}")
        else:
            copies[nom] = texte

    racine = RACINE / FICHIER
    if racine.exists():
        copies["racine"] = racine.read_text()

    if len(copies) < 2:
        print("rien à comparer.")
        return 1

    if options.aligner_la_racine:
        source = options.aligner_la_racine
        if source not in copies:
            print(f"✗  {source} est illisible — rien recopié.")
            return 1
        racine.write_text(copies[source])
        print(f"racine alignée sur {source} ({len(copies[source].splitlines())} lignes).")
        return 0

    # ## Dire QUI porte chaque titre, plutôt que ce qui manque à chacun
    #
    # La première version listait, pour chaque copie, les titres qu'elle n'avait
    # pas. Sur une section **renommée**, ça donnait « les trois dépôts manquent
    # d'un titre » alors que l'ancien nom ne survivait que dans la racine — le
    # rapport accusait les copies à jour.
    #
    # En disant qui porte quoi, un titre présent partout sauf ici se lit comme
    # une perte, et un titre présent nulle part sauf là comme un reliquat. La
    # même donnée, mais l'anomalie saute aux yeux au lieu de se répartir.
    porteurs: dict[str, list[str]] = {}
    ordre: list[str] = []
    for nom, texte in copies.items():
        for t in titres(texte):
            if t not in porteurs:
                porteurs[t] = []
                ordre.append(t)
            porteurs[t].append(nom)

    largeur = max(len(n) for n in copies)
    for nom, texte in copies.items():
        print(f"  {nom:<{largeur}}  {len(titres(texte)):>2} titres")

    partages = [t for t in ordre if len(porteurs[t]) != len(copies)]
    if not partages:
        print(f"\nLes {len(copies)} exemplaires concordent.")
        return 0

    print()
    for t in partages:
        chez = porteurs[t]
        absents = [n for n in copies if n not in chez]
        if len(chez) == 1:
            print(f"  seul {chez[0]} porte :\n      {t}")
        elif len(absents) == 1:
            print(f"  {absents[0]} ne porte pas :\n      {t}")
        else:
            print(f"  {', '.join(absents)} ne portent pas :\n      {t}")
        print()

    print(
        "Porter ce qui manque dans chaque dépôt — jamais l'inverse : recopier\n"
        "depuis la racine impose son retard aux autres, c'est ce qui a effacé\n"
        "la section du worktree le 25 août.\n"
        "La racine s'aligne en dernier : --aligner-la-racine <DÉPÔT>."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
