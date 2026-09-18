"""Le nombre de livres écrits, lu dans le corpus plutôt qu'écrit à la main.

La vitrine de l'App Store annonçait « Trois livres sur soixante-dix » à quatre
endroits — `fiche.py`, `soumettre.py` deux fois, `vitrine.py` — pendant qu'il y
en avait **cinq**. Le chiffre datait du 19 août 2026 ; le cinquième livre est
entré le 11 septembre, et personne n'a pensé aux quatre phrases.

L'ironie est dans la phrase elle-même : « Le compte est public, et il est tenu
par le corpus lui-même. » Il l'était partout sauf là où on l'annonçait.

C'est la forme qu'on retire depuis dix jours — un texte qui affirme ce qu'une
donnée sait déjà. Le remède n'est pas de corriger les quatre phrases : c'est de
leur retirer le droit de le dire. Une seule source, et elle se relit à chaque
build.

    from compte_du_corpus import phrase
    phrase()            # « Cinq livres sur soixante-dix »
    phrase(bas=True)    # « cinq livres sur soixante-dix »

**Pourquoi le corpus embarqué et non `dist/`.** `app/Resources/data/corpus.json`
est committé ; `dist/` est engendré. La fiche se pousse depuis la CI, qui ne
construit pas le corpus avant d'écrire le texte de l'App Store — lire `dist/`
demanderait de faire dépendre la fiche du pipeline, pour un nombre que le dépôt
porte déjà.
"""

import json
import pathlib

RACINE = pathlib.Path(__file__).resolve().parents[1]
CORPUS = RACINE / "app" / "Resources" / "data" / "corpus.json"

# Jusqu'à soixante-dix, parce que c'est le compte des livres et qu'il ne
# grandira pas. Au-delà, on rendrait le chiffre plutôt que d'inventer une
# mécanique de numération française pour un cas qui n'arrive pas.
_LETTRES = {
    0: "aucun", 1: "un", 2: "deux", 3: "trois", 4: "quatre", 5: "cinq",
    6: "six", 7: "sept", 8: "huit", 9: "neuf", 10: "dix", 11: "onze",
    12: "douze", 13: "treize", 14: "quatorze", 15: "quinze", 16: "seize",
    17: "dix-sept", 18: "dix-huit", 19: "dix-neuf", 20: "vingt",
    30: "trente", 40: "quarante", 50: "cinquante", 60: "soixante",
    70: "soixante-dix",
}


def en_lettres(n: int) -> str:
    """Le nombre en toutes lettres, ou le chiffre si on ne sait pas le dire.

    Une phrase de vitrine ne porte pas de chiffres arabes — « Trois livres »
    et non « 3 livres ». Rendre le chiffre hors table est un repli visible :
    la phrase reste juste, et sa laideur dit qu'il faut allonger la table.
    """
    return _LETTRES.get(n, str(n))


def compter() -> tuple[int, int]:
    """(livres écrits, livres déclarés), lus dans le corpus embarqué.

    Un livre est « écrit » quand il n'est pas `empty` — c'est le même drapeau
    que la liseuse emploie pour décider si une ligne du sommaire est cliquable.
    Compter autrement ferait diverger la vitrine de ce que le lecteur voit.
    """
    corpus = json.loads(CORPUS.read_text(encoding="utf8"))
    ecrits = total = 0
    for section in corpus["corpora"]:
        for mode in section.get("modes", []):
            for livre in mode.get("books", []):
                total += 1
                if not livre.get("empty", True):
                    ecrits += 1
    return ecrits, total


def phrase(bas: bool = False) -> str:
    """« Cinq livres sur soixante-dix » — la forme employée par les trois textes.

    `bas` rend l'initiale minuscule, pour les phrases où le compte n'ouvre pas
    la phrase (la note au relecteur d'Apple le place après une virgule).
    """
    ecrits, total = compter()
    mot = en_lettres(ecrits)
    return f"{mot if bas else mot.capitalize()} livres sur {en_lettres(total)}"


if __name__ == "__main__":
    ecrits, total = compter()
    print(f"{phrase()}  ({ecrits}/{total})")
