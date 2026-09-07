#!/usr/bin/env bash
#
# Éprouve les scripts shell du dépôt, sans les exécuter.
#
#   ./scripts/eprouver-les-scripts.sh
#
# Deux motifs, et rien d'autre. Chacun a coûté une livraison le 31 août 2026,
# et aucun n'est visible à la lecture — c'est ce qui les qualifie :
#
#   1. **une variable collée à un caractère non-ASCII** — bash lit `$gris→`
#      comme un seul nom, ne le trouve pas, et `set -u` arrête tout. Le message
#      accuse une variable qui n'existe pas plutôt que la ligne qui l'invente ;
#
#   2. **`xcodebuild` dans un tuyau qui se ferme tôt** — `head` ferme le
#      descripteur, `xcodebuild` écrit sa seconde ligne dedans, et celui
#      d'Xcode 27 lève une exception non rattrapée : `SIGABRT`, code 134, et
#      non le 141 qu'on cherche quand on soupçonne un `SIGPIPE`.
#
# **Ce qu'il n'attrape pas**, et il faut le dire pour qu'on ne s'y fie pas plus
# qu'il ne mérite : toute la logique. Un canal mal dérivé, une garde absente,
# un `trap` oublié passent ici sans un mot. Il ne connaît que deux formes.
#
# Les commentaires sont ignorés — un contrôle qui signale la documentation de
# ses propres défauts est un contrôle qu'on désactive.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; fin=$'\033[0m'
fautes=0

for f in scripts/*.sh .github/scripts/*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f" 2>/dev/null; then
    printf '%s✗%s %s ne se lit pas\n' "$rouge" "$fin" "$f"; fautes=$((fautes + 1))
  fi
done

# Les deux motifs, en Python : une expression rationnelle sur des octets
# multi-octets se décrit mal en `grep` portable.
python3 - <<'PY' || fautes=$((fautes + 1))
import glob, io, re, sys

colle = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])")
tuyau = re.compile(r"xcodebuild[^|\n]*\|\s*(head|grep -m ?1)")
fautes = 0

for chemin in sorted(glob.glob("scripts/*.sh")) + sorted(glob.glob(".github/scripts/*.sh")):
    for n, ligne in enumerate(io.open(chemin, encoding="utf-8"), 1):
        if ligne.lstrip().startswith("#"):
            continue
        for m in colle.finditer(ligne):
            print(f"  ✗ {chemin}:{n} — ${m.group(1)} collé à un caractère non-ASCII ; "
                  f"écrire ${{{m.group(1)}}}")
            fautes += 1
        if tuyau.search(ligne):
            print(f"  ✗ {chemin}:{n} — xcodebuild dans un lecteur qui se ferme tôt ; "
                  "capturer la sortie entière puis la découper")
            fautes += 1
sys.exit(1 if fautes else 0)
PY

if [ "$fautes" -eq 0 ]; then
  printf '%s✓%s les scripts se lisent, et ne portent aucun des deux motifs\n' "$vert" "$fin"
else
  exit 1
fi
