#!/usr/bin/env python3

"""Le simulateur des captures, démarré et vérifié.

    ./scripts/simulateur.py "ONT Pro Max" 1320 2868

Rend l'identifiant du simulateur nommé, après l'avoir démarré s'il dormait et
s'être assuré que sa dalle rend bien la taille attendue.

## Pourquoi on réutilise les simulateurs nommés

`captures.sh` créait « Captures 6.9 » et « Captures 13 » à côté de `ONT`,
`ONT Pro Max` et `ONT iPadOS`, qui existent déjà sur la machine. Deux appareils
de plus, chacun avec son conteneur de plusieurs gigaoctets, pour rendre
exactement ce que les autres rendent.

## Pourquoi on vérifie quand même la taille

Un nom ne dit pas une résolution. `ONT` est un iPhone 17 Pro : il rend
1206 × 2622, quand l'emplacement 6,9″ de l'App Store n'accepte que 1320 × 2868
— d'où `ONT Pro Max`, qui existe pour ça.

La mesure est prise sur une **vraie capture**, la seule qui ne puisse pas
mentir là où un type d'appareil peut tromper. Et elle est prise **avant** de
rien construire : ce qui n'est pas vérifié tôt se découvre tard, à la fin d'une
chaîne de plusieurs minutes, ou pas du tout — une capture à la mauvaise taille
qu'Apple accepterait déformerait la vitrine sans que rien ne le signale.
"""

import json
import os
import subprocess
import sys
import tempfile


def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)


def appareils():
    return json.loads(simctl("list", "devices", "-j").stdout)["devices"]


def mesurer(udid: str) -> list[int]:
    """La taille de la dalle, relevée sur une vraie capture."""
    with tempfile.TemporaryDirectory() as dossier:
        essai = os.path.join(dossier, "essai.png")
        simctl("io", udid, "screenshot", essai)
        if not os.path.exists(essai):
            return []
        mesure = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", essai],
            capture_output=True,
            text=True,
        ).stdout
    return [int(l.split(":")[1]) for l in mesure.splitlines() if "pixel" in l]


def demarrer(udid: str) -> None:
    simctl("boot", udid)
    simctl("bootstatus", udid, "-b")


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(f"usage : {sys.argv[0]} <nom> <largeur> <hauteur>")
    nom, largeur, hauteur = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

    trouves = [
        (d["udid"], d["state"])
        for liste in appareils().values()
        for d in liste
        if d["name"] == nom
    ]
    if not trouves:
        sys.exit(
            f"le simulateur « {nom} » n'existe pas.\n"
            f"  Créez-le dans Xcode, ou renommez celui qui doit servir aux captures."
        )
    udid, etat = trouves[0]

    if etat != "Booted":
        demarrer(udid)

    vus = mesurer(udid)
    if not vus:
        sys.exit(f"« {nom} » n'a rendu aucune capture — a-t-il démarré ?")

    # Le paysage, rattrapé tout seul.
    #
    # Un simulateur garde l'orientation où on l'a laissé. `ONT iPadOS` était en
    # paysage, et rendait donc du 2752 × 2064 — la taille attendue, tournée d'un
    # quart de tour.
    #
    # Trois façons de le remettre debout, et une seule qui tient ici :
    #
    #   · `simctl` — il ne sait pas. `simctl ui` ne connaît que l'apparence, le
    #     contraste et le corps du texte ;
    #   · le menu de **Device Hub** — l'app des simulateurs depuis Xcode 27, et
    #     non `Simulator.app`. Elle n'est pas forcément ouverte quand les
    #     appareils sont démarrés par `simctl`, et la piloter demanderait des
    #     événements synthétisés, que la permission d'accessibilité refuse au
    #     terminal. Une chaîne de captures ne peut pas dépendre de ça ;
    #   · le **redémarrage**, qui rend l'orientation par défaut. Aucune
    #     interface, aucune permission, et c'est déjà le geste qui rattrape
    #     l'écran atténué par la veille.
    #
    # On ne le tente que sur l'échange exact. Une autre taille n'est pas une
    # rotation, c'est le mauvais appareil, et redémarrer n'y changerait rien.
    if vus == [hauteur, largeur]:
        print(f"  « {nom} » était en paysage — redémarrage", file=sys.stderr)
        simctl("shutdown", udid)
        demarrer(udid)
        vus = mesurer(udid)

    if vus != [largeur, hauteur]:
        sys.exit(
            f"« {nom} » rend du {vus[0]} × {vus[1]}, or l'App Store attend "
            f"{largeur} × {hauteur}.\n"
            f"  Changez le type d'appareil de ce simulateur dans Xcode, ou donnez "
            f"ce nom à un simulateur qui a la bonne dalle."
        )

    print(udid)


if __name__ == "__main__":
    main()
