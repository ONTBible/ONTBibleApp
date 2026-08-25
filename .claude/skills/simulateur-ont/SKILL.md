---
name: simulateur-ont
description: Compiler, installer et lancer La Bible ONT sur le simulateur de l'auteur, en prendre une capture. À employer dès qu'il faut montrer ou vérifier quelque chose à l'écran de l'app iOS — « lance le sim », « on va voir ça ensemble », ou avant de dire qu'un changement d'interface est fait.
---

# Le simulateur de l'auteur s'appelle ONT

Il y a **un** simulateur pour ce projet, et il porte un nom : `ONT`. C'est sa
fenêtre que l'auteur a ouverte, c'est elle qu'il regarde. En amorcer un autre ne
fait pas que perdre du temps : ça installe le build sur un appareil que personne
ne regarde, et on annonce « c'est à l'écran » alors que l'écran de l'auteur n'a
pas bougé.

**Le résoudre par son nom, jamais autrement.**

```bash
SIM=$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys;print(next(d['udid'] for v in json.load(sys.stdin)['devices'].values() for d in v if d['name']=='ONT'))")
```

Ni par UDID écrit en dur — il change si l'appareil est recréé —, ni par « le
premier iPhone trouvé ». C'est cette dernière commodité qui a amorcé un
*iPhone Air* le 25 août 2026, à côté du simulateur `ONT` déjà allumé.

Si aucun appareil ne s'appelle `ONT`, **le dire et s'arrêter** plutôt que d'en
choisir un autre : c'est à l'auteur de décider sur quoi il regarde.

## Le cycle complet

```bash
cd ~/ONTBible/ONTBibleApp/app
xcodegen generate --quiet                    # le projet suit project.yml
xcodebuild build -scheme ONT -destination "id=$SIM" 2>&1 \
  | grep -E "^/.*error: |^\*\* BUILD"        # ← le filtre importe, voir plus bas
xcrun simctl boot "$SIM" 2>/dev/null || true
APP=~/Library/Developer/Xcode/DerivedData/ONT-*/Build/Products/Debug-iphonesimulator/ONT.app
xcrun simctl install "$SIM" $APP
xcrun simctl launch "$SIM" com.labibleont.ONT
```

**Le filtre de `xcodebuild` se choisit avec soin.** `grep -E "error:|BUILD"`
paraît juste et ne l'est pas : la sortie contient des dizaines de variables
`BUILD_DIR`, `BUILD_ROOT`… qui saturent un `head` avant que la ligne
`** BUILD SUCCEEDED **` n'arrive. On croit alors n'avoir ni erreur ni succès.
Ancrer en début de ligne — `^/.*error: ` et `^\*\* BUILD` — et lire le résultat
jusqu'au bout.

## Regarder l'écran

```bash
xcrun simctl io "$SIM" screenshot /tmp/ont.png
```

Puis lire l'image. Deux pièges :

- **Le HTML sérialisé n'est pas le rendu.** Sur le site comme dans une capture
  d'écran d'îlot de données, `titre` porte le nom ONT (« Bereshit 1 ») alors que
  le libellé affiché est composé (« Chapitre 1 »). Lire ce qui est *rendu*.
- **`simctl` ne sait pas toucher l'écran.** Pas de navigation programmatique
  vers un onglet ; l'app s'ouvre là où elle était. Pour montrer un écran précis,
  ou bien passer par le schéma d'URL — `ont://read/<livre>/<unité>` —, ou bien
  demander à l'auteur d'y aller.

## Le thème

```bash
xcrun simctl ui "$SIM" appearance light   # ou dark
```

Le parchemin est le thème par défaut de l'app et ne suit pas ce réglage
système ; il ne sert qu'à éprouver les thèmes clair et sombre.
