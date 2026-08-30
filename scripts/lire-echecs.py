#!/usr/bin/env python3
"""Nomme les épreuves qui ont échoué, depuis le résumé d'un `.xcresult`.

    python3 scripts/lire-echecs.py resume-mac.json

Écrit pour `tests.yml`, étape « Ce que le Mac a vraiment dit ». Il existe
parce qu'un `exit 65` sans nom d'épreuve oblige le suivant à refaire l'enquête
depuis zéro — une garde qui s'arrête bien mais n'enseigne rien.

Tolérant à la forme : `xcresulttool` a déjà changé de schéma, et un diagnostic
qui tombe en lisant un diagnostic ne sert personne. Il préfère ne rien dire
plutôt que lever.
"""

import json
import sys

try:
    resume = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as erreur:  # noqa: BLE001 — voir le module.
    print(f"  paquet de résultats illisible — {erreur}")
    raise SystemExit(0)

echecs = resume.get("testFailures") or []
if not echecs:
    total = resume.get("totalTestCount")
    passees = resume.get("passedTests")
    print(f"  aucune ({passees}/{total} réussies) — l'échec est ailleurs qu'à l'exécution")
    raise SystemExit(0)

for echec in echecs:
    cible = echec.get("targetName") or "?"
    nom = echec.get("testName") or echec.get("testIdentifier") or "?"
    print(f"  ✘ {cible} · {nom}")
    for ligne in (echec.get("failureText") or "").strip().splitlines():
        print(f"      {ligne}")
