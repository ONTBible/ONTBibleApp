#!/usr/bin/env python3

"""Les captures brutes deviennent des affiches.

    ./scripts/vitrine.py

## Pourquoi une affiche et pas la capture

Une capture d'écran nue rend deux services à personne. Dans la fiche de l'App
Store elle arrive en vignette, où l'interface n'est plus lisible ; et dans un
lien partagé, iMessage la reprend telle quelle et fabrique une carte où rien
ne se voit — c'est le défaut relevé le 19 août 2026 sur le lien de l'app.

Le détail qui décide, et qu'on ne devine pas : Apple **échantillonne la
couleur de fond de la capture n°1** et la sert dans le JSON de la fiche
(`backgroundColor`). iMessage en teinte toute la bulle. Une première capture
sur parchemin donnait donc une carte blafarde. Le fond de nuit ne rend pas
seulement l'affiche lisible, il assombrit la carte entière.

## La disposition

Celle de toutes les fiches qui tiennent : marque, accroche, phrase, appareil
qui déborde par le bas. Les quatre écrans reprennent, mot pour mot, la
description de la fiche — on n'écrit pas une deuxième fois ce qui est déjà
écrit, sinon les deux divergent.

## Ce dont ça dépend

Les polices du dépôt, `app/Resources/Fonts` — pas celles de la machine. Une
affiche qui se compose ici et pas dans la CI n'est pas reproductible.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RACINE = Path(__file__).resolve().parent.parent
POLICES = RACINE / "app/Resources/Fonts"
CAPTURES = RACINE / "app/Captures"

# La palette, relevée sur `ONTColors.swift`. Le bordeaux et l'or viennent du
# logo ; la nuit est le fond de `ontbible.com`. Aucune teinte inventée ici.
NUIT = (0x18, 0x09, 0x0D)
BORDEAUX = (0x42, 0x1B, 0x26)
OR = (0xCD, 0xBE, 0x83)
ENCRE_VIVE = (0xED, 0xE3, 0xD6)
ENCRE_DOUCE = (0xB3, 0xA5, 0x9B)

# Les quatre écrans, dans l'ordre de `captures.sh`. Les coupures de ligne du
# titre sont écrites à la main : une coupure automatique place le verbe seul
# sur la dernière ligne une fois sur deux.
AFFICHES = [
    (
        ["Le cosmos hébreu", "n’est pas une usine.", "C’est un Temple."],
        "Une restitution française du corpus hébreu et araméen "
        "antique, fondée sur l’ontologie hébraïque fonctionnelle.",
    ),
    (
        ["Trois niveaux,", "jamais confondus."],
        "Ce que l’hébreu dit, ce qu’il portait pour son lecteur, "
        "et le mot original. Chaque niveau s’éteint d’un geste.",
    ),
    (
        ["Les intraduisibles", "restent debout."],
        "Elohim, neshamah, kavod, ruach. Les rendre coûterait ce "
        "qu’ils portent : chacun a sa fiche.",
    ),
    (
        ["Un chantier", "ouvert."],
        "Trois livres sur soixante-dix. Le compte est public, et "
        "il est tenu par le corpus lui-même.",
    ),
]


def police(nom, taille):
    return ImageFont.truetype(str(POLICES / nom), taille)


def fond(largeur, hauteur):
    """Le dégradé bordeaux → nuit, du haut vers le bas.

    Peint ligne à ligne sur une image d'un pixel de large, puis étiré : un
    dégradé calculé pour chaque pixel de la largeur coûte deux secondes par
    affiche et rend exactement la même chose.
    """
    colonne = Image.new("RGB", (1, hauteur))
    dessin = ImageDraw.Draw(colonne)
    for y in range(hauteur):
        t = y / (hauteur - 1)
        # Une progression au carré : le bordeaux tient le haut, où se pose le
        # texte, et la nuit prend le bas, où l'appareil se détache.
        t = t * t
        dessin.point((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BORDEAUX, NUIT)))
    return colonne.resize((largeur, hauteur), Image.BICUBIC)


def tracer(dessin, xy, texte, fonte, couleur, interlettre):
    """Un texte à interlettrage — PIL ne sait pas l'espacer tout seul."""
    x, y = xy
    for caractere in texte:
        dessin.text((x, y), caractere, font=fonte, fill=couleur)
        x += dessin.textlength(caractere, font=fonte) + interlettre
    return x - interlettre - xy[0]


def largeur_suivie(dessin, texte, fonte, interlettre):
    return sum(dessin.textlength(c, font=fonte) for c in texte) + interlettre * (len(texte) - 1)


def ajuster(dessin, lignes, nom_police, corps_max, largeur_max):
    """Le plus grand corps où la ligne la plus longue tient dans la largeur.

    Écrit ainsi et non réglé une fois pour toutes : « Les intraduisibles » et
    « Un chantier » n'ont pas la même longueur, l'iPhone et l'iPad n'ont pas la
    même largeur, et un corps unique donnait un titre qui touchait les deux
    bords sur la moitié des affiches. Le corps est une conséquence du texte.
    """
    corps = corps_max
    while corps > 8:
        fonte = police(nom_police, corps)
        if max(dessin.textlength(l, font=fonte) for l in lignes) <= largeur_max:
            return fonte, corps
        corps -= 1
    return police(nom_police, corps), corps


def couper(dessin, texte, fonte, largeur_max):
    lignes, courante = [], ""
    for mot in texte.split():
        essai = f"{courante} {mot}".strip()
        if dessin.textlength(essai, font=fonte) <= largeur_max or not courante:
            courante = essai
        else:
            lignes.append(courante)
            courante = mot
    return lignes + [courante]


# Le châssis. L'arête est **dorée** et non grise : c'est le titane désert, une
# finition qui existe, et c'est celle que prend le mockup de YouVersion. Elle
# tombe juste — l'or est déjà la couleur de la marque, et un rail gris aurait
# introduit la seule teinte froide de l'affiche.
CHASSIS = (0x2A, 0x21, 0x24)  # le corps, dans l'ombre
RAIL = OR                     # l'arête qui prend la lumière
LUNETTE = (0x07, 0x07, 0x09)  # le noir entre l'arête et la dalle


def arrondi(taille, rayon, remplissage):
    """Un rectangle arrondi, tracé au quadruple puis réduit.

    Un arrondi tracé à la taille finale sort en escalier, et l'escalier se voit
    sur un fond sombre.
    """
    n = 4
    largeur, hauteur = taille
    masque = Image.new("L", (largeur * n, hauteur * n), 0)
    ImageDraw.Draw(masque).rounded_rectangle(
        (0, 0, largeur * n - 1, hauteur * n - 1), radius=rayon * n, fill=255
    )
    masque = masque.resize(taille, Image.LANCZOS)
    plaque = Image.new("RGBA", taille, remplissage + (0,))
    plaque.putalpha(masque)
    return plaque, masque


# La Dynamic Island, en fractions de la largeur de l'écran. Relevées sur
# l'iPhone 17 Pro Max : 440 × 956 pt d'écran, une pilule de 125 × 37 pt posée à
# 11 pt du bord haut.
ILE = (125 / 440, 37 / 440, 11 / 440)


def appareil(capture, largeur_cible, cadre):
    """La capture montée dans un châssis d'appareil.

    ## Pourquoi ce n'est pas un rectangle arrondi

    Ça l'a été, et l'affiche s'est fait prendre pour un appareil Android. Un
    rectangle nu ne dit pas « iPhone » : ce qui le dit, c'est l'arête de titane
    qui prend la lumière, la lunette noire, les boutons sur la tranche, et la
    Dynamic Island. Aucun de ces quatre éléments n'est dans la capture —
    `simctl` ne rend que la dalle — donc tous se dessinent ici.

    L'écran n'est pas non plus arrondi à même le bord. Il l'a été, et le coin
    mangeait la barre d'état : sur une capture, l'heure touche le bord haut, là
    où un vrai appareil garde une lunette.

    ## Ce qui change d'un appareil à l'autre

    Tout est dans `CADRES`, en fractions de la largeur : l'iPad a une lunette
    plus fine, des coins bien moins arrondis, deux boutons au lieu de quatre,
    et **pas d'île** — la caméra de l'iPad Pro M5 est sur le bord long,
    invisible en portrait.
    """
    bordure = max(3, round(largeur_cible * cadre["bordure"]))
    rayon = round(largeur_cible * cadre["rayon"])
    saillie = max(2, round(largeur_cible * 0.007))
    # L'arête est épaisse à dessein. Un filet d'un pixel disparaît dès que
    # l'affiche est vue en vignette, et c'est précisément là qu'elle doit dire
    # « iPhone ».
    trait = max(2, round(largeur_cible * 0.010))

    largeur_ecran = largeur_cible - bordure * 2
    hauteur_ecran = round(largeur_ecran * capture.height / capture.width)
    hauteur_cible = hauteur_ecran + bordure * 2

    vignette = Image.new(
        "RGBA", (largeur_cible + saillie * 2, hauteur_cible + saillie), (0, 0, 0, 0)
    )
    dessin = ImageDraw.Draw(vignette)

    # Les boutons d'abord : ils sortent de la tranche, et le châssis vient
    # ensuite recouvrir la part qui rentre dedans. Les départs et longueurs
    # comptent le long de la tranche — en hauteur sur les côtés, en largeur sur
    # le dessus, où l'iPad porte sa veille.
    for cote, depart, longueur in cadre["boutons"]:
        if cote == "haut":
            a = saillie + round(largeur_cible * depart)
            boite = (a, 0, a + round(largeur_cible * longueur), saillie + bordure)
        else:
            a = saillie + round(hauteur_cible * depart)
            b = a + round(hauteur_cible * longueur)
            if cote == "gauche":
                boite = (0, a, saillie + bordure, b)
            else:
                boite = (saillie + largeur_cible - bordure, a, largeur_cible + saillie * 2 - 1, b)
        dessin.rounded_rectangle(boite, radius=saillie, fill=RAIL)

    corps, _ = arrondi((largeur_cible, hauteur_cible), rayon, CHASSIS)
    ImageDraw.Draw(corps).rounded_rectangle(
        (trait / 2, trait / 2, largeur_cible - trait / 2 - 1, hauteur_cible - trait / 2 - 1),
        radius=rayon,
        outline=RAIL + (255,),
        width=trait,
    )

    # La lunette noire, encastrée entre l'arête et la dalle.
    creux = trait
    noir, masque_noir = arrondi(
        (largeur_cible - creux * 2, hauteur_cible - creux * 2), max(1, rayon - creux), LUNETTE
    )
    corps.paste(noir, (creux, creux), masque_noir)

    ecran = capture.convert("RGB").resize((largeur_ecran, hauteur_ecran), Image.LANCZOS)
    if cadre["ile"]:
        large, haut, marge = (round(largeur_ecran * f) for f in ILE)
        gauche = (largeur_ecran - large) // 2
        pilule, masque_pilule = arrondi((large, haut), haut // 2, (0, 0, 0))
        ecran.paste(pilule.convert("RGB"), (gauche, marge), masque_pilule)
        # L'objectif, un cran plus clair que la pilule. Invisible en vignette,
        # mais l'affiche est aussi regardée en grand dans la fiche.
        oeil = round(haut * 0.42)
        ImageDraw.Draw(ecran).ellipse(
            (
                gauche + large - round(haut * 0.78),
                marge + (haut - oeil) // 2,
                gauche + large - round(haut * 0.78) + oeil,
                marge + (haut + oeil) // 2,
            ),
            fill=(0x1C, 0x1C, 0x22),
        )

    _, masque_ecran = arrondi((largeur_ecran, hauteur_ecran), max(1, rayon - bordure), (0, 0, 0))
    corps.paste(ecran, (bordure, bordure), masque_ecran)

    # L'objectif de l'iPad, posé sur la lunette et non dans l'écran.
    #
    # Sur le bord **long**, donc à droite en portrait : depuis l'iPad Pro M4 la
    # caméra a déménagé pour qu'on soit cadré droit en visio, l'iPad posé en
    # paysage. C'est le détail qui date un mockup — le mettre en haut, c'est
    # dessiner un iPad d'avant 2024.
    if cadre.get("camera"):
        cote, hauteur_relative = cadre["camera"]
        oeil = max(2, round(largeur_cible * 0.005))
        centre_x = largeur_cible - (bordure + trait) / 2 if cote == "droite" else (bordure + trait) / 2
        centre_y = hauteur_cible * hauteur_relative
        ImageDraw.Draw(corps).ellipse(
            (centre_x - oeil, centre_y - oeil, centre_x + oeil, centre_y + oeil),
            fill=(0x1C, 0x1C, 0x22),
        )

    vignette.alpha_composite(corps, (saillie, saillie))
    return vignette


def ombre(taille_vignette, rayon, flou, decalage):
    marge = flou * 3
    largeur, hauteur = taille_vignette
    plaque = Image.new("RGBA", (largeur + marge * 2, hauteur + marge * 2), (0, 0, 0, 0))
    ImageDraw.Draw(plaque).rounded_rectangle(
        (marge, marge + decalage, marge + largeur, marge + hauteur + decalage),
        radius=rayon,
        fill=(0, 0, 0, 150),
    )
    return plaque.filter(ImageFilter.GaussianBlur(flou)), marge


def affiche(chemin_capture, titre, phrase, cadre):
    capture = Image.open(chemin_capture)
    L, H = capture.size

    toile = fond(L, H).convert("RGBA")
    dessin = ImageDraw.Draw(toile)

    # Tout se mesure sur la largeur, jamais sur la hauteur : l'iPhone et
    # l'iPad n'ont pas la même proportion, et un corps de texte réglé sur la
    # hauteur sortirait deux fois plus gros sur l'un que sur l'autre.
    marge = round(L * 0.075)
    f_marque = police("Jost-Regular.ttf", round(L * 0.038))
    f_titre, corps_titre = ajuster(
        dessin, titre, "Literata-SemiBold.ttf", round(L * 0.103), L * 0.86
    )
    f_phrase = police("Literata-Regular.ttf", round(L * 0.040))
    interlettre = round(L * 0.038 * 0.18)

    y = marge

    marque = "LA BIBLE ONT"
    largeur_marque = largeur_suivie(dessin, marque, f_marque, interlettre)
    tracer(dessin, ((L - largeur_marque) / 2, y), marque, f_marque, OR, interlettre)
    y += round(L * 0.038 * 1.2) + round(L * 0.055)

    hauteur_ligne = round(corps_titre * 1.16)
    for ligne in titre:
        dessin.text((L / 2, y), ligne, font=f_titre, fill=ENCRE_VIVE, anchor="ma")
        y += hauteur_ligne
    y += round(L * 0.042)

    # La phrase est tenue plus étroite que le titre : une ligne de soixante
    # signes se relit, une ligne qui court sur toute la largeur non.
    for ligne in couper(dessin, phrase, f_phrase, L * 0.74):
        dessin.text((L / 2, y), ligne, font=f_phrase, fill=ENCRE_DOUCE, anchor="ma")
        y += round(L * 0.040 * 1.42)

    y += round(L * 0.070)

    largeur_appareil = round(L * 0.735)
    vignette = appareil(capture, largeur_appareil, cadre)
    x = (L - vignette.width) // 2
    plaque, decalage_ombre = ombre(
        vignette.size,
        round(largeur_appareil * cadre["rayon"]),
        round(L * 0.028),
        round(L * 0.012),
    )
    toile.alpha_composite(plaque, (x - decalage_ombre, y - decalage_ombre))
    toile.alpha_composite(vignette, (x, y))

    return toile.convert("RGB")


# Les châssis, en fractions de la largeur de l'appareil. Les boutons sont
# donnés en fractions de sa hauteur : (côté, départ, longueur).
#
# Un dossier Android s'ajoutera ici le jour venu — sans île, coins moins
# arrondis, rail neutre — et rien d'autre ne bougera.
CADRES = {
    "iphone-6.9": {
        "ile": True,
        "bordure": 0.030,
        "rayon": 0.145,
        "boutons": [
            ("gauche", 0.112, 0.028),  # le bouton Action
            ("gauche", 0.162, 0.056),  # volume +
            ("gauche", 0.232, 0.056),  # volume −
            ("droite", 0.176, 0.088),  # veille, et la commande d'appareil photo
        ],
    },
    # L'iPad ne se dessine pas comme un grand iPhone : lunette large et
    # symétrique — la dalle ne va pas au bord —, coins trois fois moins
    # arrondis, veille sur la tranche haute, volume sur la tranche droite, et
    # la caméra sur le bord long.
    "ipad-13": {
        "ile": False,
        "bordure": 0.030,
        "rayon": 0.046,
        "boutons": [
            ("haut", 0.720, 0.075),  # veille
            ("droite", 0.055, 0.032),  # volume +
            ("droite", 0.100, 0.032),  # volume −
        ],
        "camera": ("droite", 0.5),
    },
}


def main():
    for dossier, cadre in CADRES.items():
        source = CAPTURES / "brut" / dossier
        if not source.is_dir():
            sys.exit(f"manque {source} — lancer ./scripts/captures.sh d'abord")
        cible = CAPTURES / dossier
        cible.mkdir(parents=True, exist_ok=True)
        for i, (titre, phrase) in enumerate(AFFICHES, start=1):
            nom = f"{i:02d}.png"
            image = affiche(source / nom, titre, phrase, cadre)
            image.save(cible / nom)
            print(f"  {cible.relative_to(RACINE)}/{nom}  {image.width}×{image.height}")


if __name__ == "__main__":
    main()
