#!/usr/bin/env bash
#
# Regrave `app/Resources/Media.xcassets/AppIconMac.appiconset` depuis
# `app/ONT.icon`, pour que les deux liseuses montrent la même icône.
#
#   ./scripts/graver-l-icone-du-mac.sh
#
# ## Pourquoi une icône du Mac vit à part
#
# L'iPhone porte le bundle Icon Composer. Le Mac ne peut pas, et c'est un étau
# mesuré le 31 août 2026 :
#
#   - l'`actool` d'Xcode **26.3** — la version publiée, celle des runners
#     GitHub — **plante** en composant un bundle Icon Composer pour macOS ;
#   - celui d'Xcode **27** le compose, mais Apple **refuse les binaires
#     construits avec un Xcode bêta**. Constaté à l'envoi, après que l'archive
#     et l'export ont réussi : « This bundle is invalid. Apple is not currently
#     accepting applications built with this version of Xcode. »
#
# Les deux issues s'excluaient. Le `.appiconset` est la troisième : format
# d'avant Icon Composer, qu'Xcode 26.3 compose sans broncher, au contenu
# identique puisqu'il est **gravé depuis le bundle lui-même**.
#
# **C'est un pont, pas une destination.** Le jour où Xcode 27 sort en version
# publiée : supprimer l'appiconset, rendre `ONT.icon` à la cible macOS dans
# `scripts/patch-app-icon.rb`, et jeter ce fichier.
#
# ## Ce qu'il faut
#
# Un Xcode dont l'`actool` compose `ONT.icon` pour macOS — 27 le fait, 26.3 non.
# Le script le vérifie plutôt que de le supposer.
set -euo pipefail

cd "$(dirname "$0")/.."
vert=$'\033[32m'; rouge=$'\033[31m'; gris=$'\033[90m'; fin=$'\033[0m'
echec() { printf '%s✗%s %s\n' "$rouge" "$fin" "$1" >&2; exit 1; }

SET="app/Resources/Media.xcassets/AppIconMac.appiconset"
TRAVAIL=$(mktemp -d)
# Le projet est rendu à son état normal quoi qu'il arrive : ce script le
# détourne le temps d'un build, et un arrêt au milieu laisserait la cible macOS
# pointée sur une icône qui la fait planter en CI.
trap 'cd "$(dirname "$0")/.." && (cd app && xcodegen generate >/dev/null 2>&1) || true; rm -rf "$TRAVAIL"' EXIT

XCODE=$(xcodebuild -version)          # sans tuyau : `head` fermerait le
XCODE=${XCODE%%$'\n'*}                 # descripteur et ferait avorter xcodebuild
echo "${gris}→ $XCODE$fin"

# ── 1. Rendre ONT.icon à la cible macOS, le temps d'un build
#
# Elle ne l'a plus : `patch-app-icon.rb` l'en retire, parce qu'`actool` compile
# *toutes* ses entrées et planterait sur 26.3 même sans la nommer.
echo "→ le projet, détourné le temps d'un build"
(cd app && xcodegen generate >/dev/null)
ruby -e '
require "xcodeproj"
p_ = Xcodeproj::Project.open("app/ONT.xcodeproj")
t = p_.targets.find { |x| x.name == "ONTMac" } or abort "cible ONTMac absente"
f = p_.files.find { |x| x.path == "ONT.icon" } or abort "ONT.icon absent du projet"
t.resources_build_phase.add_file_reference(f) unless t.resources_build_phase.files_references.include?(f)
t.build_configurations.each { |c| c.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "ONT" }
p_.save
' || echec "impossible de détourner le projet"

echo "→ le build, dont on ne garde que l'icône"
if ! xcodebuild build -project app/ONT.xcodeproj -scheme ONTMac \
      -destination 'platform=macOS' -derivedDataPath "$TRAVAIL/dd" \
      CODE_SIGNING_ALLOWED=NO > "$TRAVAIL/build.log" 2>&1; then
  grep -q "CompileAssetCatalogVariant" "$TRAVAIL/build.log" \
    && echec "cet Xcode ne compose pas ONT.icon pour macOS — il en faut un qui le sache"
  echec "la compilation échoue — voir $TRAVAIL/build.log"
fi
APP=$(find "$TRAVAIL/dd/Build/Products" -maxdepth 3 -name "*.app" -print -quit)
[ -n "$APP" ] || echec "aucune app produite"

# ── 2. Graver, en se méfiant du gabarit
cat > "$TRAVAIL/graver.swift" <<'SWIFT'
import AppKit

// **Chaque taille existe en double**, et l'un des deux exemplaires est le
// gabarit vide en pointillés que macOS affiche faute de mieux. Un `draw` naïf
// choisit parfois celui-là et rend une image aux bonnes dimensions, d'un poids
// plausible, entièrement fausse — c'est arrivé à 1024 le jour où ce script a
// été écrit, et le contrôle par la taille du fichier ne l'a pas vu.
//
// On rend donc chaque exemplaire et on garde le plus sombre : le gabarit est
// quasi blanc, l'icône est bordeaux. Grossier, et vérifiable à l'œil.
let icone = NSWorkspace.shared.icon(forFile: CommandLine.arguments[1])
let dossier = CommandLine.arguments[2]

func rendre(_ rep: NSImageRep, _ cote: Int) -> NSBitmapImageRep? {
    guard let bm = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bm)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: cote, height: cote))
    NSGraphicsContext.restoreGraphicsState()
    return bm
}

/// La clarté du centre, **et son opacité**.
///
/// Le premier critère seul — « garder le plus sombre » — écartait bien le
/// gabarit blanc, et choisissait à sa place une image **entièrement
/// transparente** : le vide est plus noir que le bordeaux. Mesuré à 1024, où
/// il a rendu `centre 0.00`.
///
/// C'est la même faute que celle qu'il corrigeait, retournée : un critère qui
/// sépare deux choses en oublie une troisième. On exige donc d'abord que le
/// centre soit **opaque**, et l'on ne compare qu'ensuite.
func centre(_ bm: NSBitmapImageRep) -> (clarte: Double, opacite: Double) {
    let c = bm.pixelsWide / 2
    guard let p = bm.colorAt(x: c, y: c) else { return (1, 0) }
    let clarte = (Double(p.redComponent) + Double(p.greenComponent) + Double(p.blueComponent)) / 3
    return (clarte, Double(p.alphaComponent))
}

let tailles: [(pixels: Int, point: Int, echelle: Int)] = [
    (16, 16, 1), (32, 16, 2), (32, 32, 1), (64, 32, 2),
    (128, 128, 1), (256, 128, 2), (256, 256, 1), (512, 256, 2),
    (512, 512, 1), (1024, 512, 2),
]

var faute = false
for t in tailles {
    let candidats = icone.representations.filter { $0.pixelsWide >= t.pixels }
        .sorted { $0.pixelsWide < $1.pixelsWide }.prefix(6)
    var meilleur: (NSBitmapImageRep, Double)?
    for rep in candidats {
        guard let bm = rendre(rep, t.pixels) else { continue }
        let (clarte, opacite) = centre(bm)
        guard opacite > 0.9 else { continue }   // le vide n'est pas un candidat
        if meilleur == nil || clarte < meilleur!.1 { meilleur = (bm, clarte) }
    }
    guard let (bm, clarte) = meilleur,
          let png = bm.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("aucun rendu à \(t.pixels)\n".data(using: .utf8)!)
        faute = true; continue
    }
    // Un centre clair est le gabarit. On refuse plutôt que de graver du vide.
    if clarte > 0.5 {
        FileHandle.standardError.write(
            "centre clair à \(t.pixels) (\(String(format: "%.2f", clarte))) — gabarit\n".data(using: .utf8)!)
        faute = true
    }
    let nom = "icon_\(t.point)x\(t.point)\(t.echelle == 2 ? "@2x" : "").png"
    try? png.write(to: URL(fileURLWithPath: "\(dossier)/\(nom)"))
    print("  \(nom.padding(toLength: 22, withPad: " ", startingAt: 0)) \(t.pixels)×\(t.pixels)  centre \(String(format: "%.2f", clarte))")
}
exit(faute ? 1 : 0)
SWIFT
swiftc -O "$TRAVAIL/graver.swift" -o "$TRAVAIL/graver" 2>/dev/null || echec "le graveur ne compile pas"

echo "→ les dix tailles"
mkdir -p "$TRAVAIL/set"
"$TRAVAIL/graver" "$APP" "$TRAVAIL/set" || echec "au moins une taille est un gabarit — rien n'a été écrit dans le dépôt"

# ── 3. Poser, avec son Contents.json
mkdir -p "$SET"
rm -f "$SET"/icon_*.png
cp "$TRAVAIL/set"/icon_*.png "$SET/"
python3 - "$SET" <<'PY'
import json, sys, io
tailles = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
images = [{"filename": f"icon_{t}x{t}{'@2x' if e == 2 else ''}.png",
           "idiom": "mac", "scale": f"{e}x", "size": f"{t}x{t}"} for t, e in tailles]
io.open(f"{sys.argv[1]}/Contents.json", "w", encoding="utf-8").write(
    json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
               indent=2, ensure_ascii=False) + "\n")
PY

printf '%s✓%s icône gravée — %s images dans %s\n' "$vert" "$fin" \
  "$(ls "$SET"/icon_*.png | wc -l | tr -d ' ')" "$SET"
cat <<TEXTE

$gris  Le projet a été rendu à son état normal. Regarder les images avant de
  committer : les dimensions et le poids ont déjà menti une fois. Une planche
  de contact se fait en une ligne —

      qlmanage -p $SET/icon_*.png
$fin
TEXTE
