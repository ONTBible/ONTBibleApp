#!/usr/bin/env python3
"""Les captures de la liseuse Android, encadrées dans leur appareil.

    ./scripts/captures-android.py                    l'écran courant
    ./scripts/captures-android.py --sortie a.png     ailleurs qu'au défaut

## Pourquoi encadrer

Le Play Store accepte des captures nues, mais une capture nue ne dit pas ce
qu'on regarde : la même image pourrait être une maquette, un site, une autre
app. Le châssis dit « ceci tourne sur un téléphone », et c'est ce que le lecteur
cherche à savoir avant d'installer.

C'est le pendant de `vitrine.py` côté App Store, en plus simple : Apple veut des
affiches composées, Google accepte l'appareil seul.

## Les mesures ne sont pas choisies

Elles sont **lues** dans le `layout` de l'habillage de l'émulateur. Un habillage
déclare la taille de sa dalle, le rayon de ses coins et l'endroit où elle se
pose dans la coque ; les recopier à la main serait garantir qu'ils dérivent le
jour où l'on change d'appareil.

C'est aussi ce qui rend l'erreur impossible : si l'AVD et l'habillage ne
décrivent pas le même écran, le script s'arrête au lieu de produire une image de
travers. C'est arrivé — un habillage de Pixel 9 Pro posé sur un profil de
Pixel 7 donnait un cadre gris et **deux encoches**, celle du masque plus celle
du système.

## Où trouver un habillage

Les paquets `android-commandlinetools` n'en contiennent aucun. Ceux d'Android
Studio conviennent :

    /Applications/Android Studio.app/Contents/plugins/android/resources/device-art-resources/<appareil>

Ils portent le nom d'« art d'appareil » parce qu'ils servent aussi à encadrer
des captures, mais leur `layout` est bien celui d'un habillage d'émulateur.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HABILLAGE_PAR_DEFAUT = Path(
    "/Applications/Android Studio.app/Contents/plugins/android/"
    "resources/device-art-resources/pixel_9_pro"
)


def mesures(habillage: Path) -> dict:
    """Ce que le `layout` de l'habillage déclare.

    On lit plutôt qu'on ne suppose : `corner_radius` manque sur les appareils
    anciens, et la position de la dalle change à chaque modèle.
    """
    texte = (habillage / "layout").read_text()

    def nombre(cle: str, defaut: int | None = None) -> int:
        trouve = re.search(rf"\b{cle}\s+(\d+)", texte)
        if trouve:
            return int(trouve.group(1))
        if defaut is None:
            raise SystemExit(f"le layout de {habillage.name} ne déclare pas « {cle} »")
        return defaut

    # `part2` porte la position de la dalle dans la coque.
    pose = re.search(r"part2 \{[^}]*?x\s+(\d+)[^}]*?y\s+(\d+)", texte, re.S)
    if not pose:
        raise SystemExit(f"le layout de {habillage.name} ne dit pas où se pose la dalle")

    return {
        "largeur": nombre("width"),
        "hauteur": nombre("height"),
        "rayon": nombre("corner_radius", 0),
        "pose": (int(pose.group(1)), int(pose.group(2))),
    }


def capturer() -> Image.Image:
    """L'écran de l'émulateur ou du téléphone branché."""
    brut = subprocess.run(
        ["adb", "exec-out", "screencap", "-p"],
        capture_output=True,
        check=True,
    ).stdout
    if not brut:
        raise SystemExit("adb n'a rien rendu — aucun appareil branché ?")
    import io

    return Image.open(io.BytesIO(brut)).convert("RGBA")


def encadrer(ecran: Image.Image, habillage: Path) -> Image.Image:
    m = mesures(habillage)

    if ecran.size != (m["largeur"], m["hauteur"]):
        raise SystemExit(
            f"l'appareil rend {ecran.size[0]}×{ecran.size[1]} mais l'habillage "
            f"{habillage.name} attend {m['largeur']}×{m['hauteur']}.\n"
            "L'AVD et l'habillage ne décrivent pas le même écran — c'est ce qui "
            "produit un cadre de travers et une encoche en double."
        )

    # Les coins de la dalle : sans eux, l'écran déborde du châssis.
    if m["rayon"]:
        masque = Image.new("L", ecran.size, 0)
        ImageDraw.Draw(masque).rounded_rectangle(
            [0, 0, ecran.size[0] - 1, ecran.size[1] - 1], m["rayon"], fill=255
        )
        ecran.putalpha(masque)

    coque = Image.open(habillage / "back.webp").convert("RGBA")
    sortie = Image.new("RGBA", coque.size, (0, 0, 0, 0))
    sortie.paste(ecran, m["pose"], ecran)
    sortie.alpha_composite(coque)

    # Le masque pose l'encoche et les reflets **par-dessus** la dalle. Il est
    # facultatif : les habillages anciens n'en ont pas.
    masque_avant = habillage / "mask.webp"
    if masque_avant.exists():
        avant = Image.open(masque_avant).convert("RGBA")
        couche = Image.new("RGBA", coque.size, (0, 0, 0, 0))
        couche.paste(avant, m["pose"], avant)
        sortie.alpha_composite(couche)

    return sortie


def main() -> None:
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument(
        "--habillage",
        type=Path,
        default=HABILLAGE_PAR_DEFAUT,
        help="le dossier de l'habillage (défaut : Pixel 9 Pro d'Android Studio)",
    )
    arguments.add_argument(
        "--sortie",
        type=Path,
        default=Path("android/captures/ecran.png"),
        help="où écrire l'image encadrée",
    )
    options = arguments.parse_args()

    if not (options.habillage / "layout").exists():
        raise SystemExit(
            f"habillage introuvable : {options.habillage}\n"
            "Les outils en ligne de commande n'en contiennent aucun ; ceux "
            "d'Android Studio conviennent — voir l'en-tête de ce fichier."
        )

    image = encadrer(capturer(), options.habillage)
    options.sortie.parent.mkdir(parents=True, exist_ok=True)
    image.save(options.sortie)
    print(f"{options.sortie}  {image.size[0]}×{image.size[1]}")


if __name__ == "__main__":
    sys.exit(main())
