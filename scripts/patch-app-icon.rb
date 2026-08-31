#!/usr/bin/env ruby
# frozen_string_literal: true

# Déclare l'icône de chaque liseuse — et elles n'ont pas la même.
#
# xcodegen ne sait pas écrire le type de fichier `wrapper.icon` dont actool a
# besoin, ni poser `ASSETCATALOG_COMPILER_APPICON_NAME`. On refait donc cette
# passe avec la gemme `xcodeproj` après chaque génération.
#
# ## Deux icônes, et pourquoi
#
# L'iPhone porte le bundle Icon Composer `app/ONT.icon`. Le Mac porte un
# `.appiconset` classique, **gravé depuis ce même bundle** par
# `scripts/graver-l-icone-du-mac.sh`.
#
# Ce n'est pas un choix esthétique, c'est un étau. L'`actool` d'Xcode 26.3 —
# la version publiée, celle des runners GitHub — **plante** en composant un
# bundle Icon Composer pour macOS, sans un mot. Celui d'Xcode 27 le compose,
# mais Apple **refuse les binaires construits avec un Xcode bêta** :
#
#     This bundle is invalid. Apple is not currently accepting applications
#     built with this version of Xcode.
#
# Mesuré le 31 août 2026, à l'envoi, après que l'archive et l'export ont
# réussi. Les deux seules issues connues s'excluaient donc l'une l'autre.
#
# Le `.appiconset` est la troisième : c'est le format d'avant Icon Composer,
# qu'Xcode 26.3 compose sans broncher, et son contenu est le rendu exact de
# `ONT.icon`. **C'est un pont, pas une destination** — le jour où Xcode 27
# sort en version publiée, on supprime l'appiconset et le Mac revient à
# `ONT.icon`, ici et dans `graver-l-icone-du-mac.sh`.
#
# Contrairement au script équivalent de Pinkha, celui-ci n'a pas à être lancé
# à la main : `project.yml` le déclare en `postGenCommand`, donc tout
# `xcodegen generate` l'exécute. Un oubli livrerait l'icône blanche par
# défaut — autant que ce soit impossible.
#
# Idempotent : le relancer ne fait rien la seconde fois.

require "xcodeproj"

ROOT         = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "app", "ONT.xcodeproj")
ICON_NAME    = "ONT.icon"          # l'iPhone
ICON_MAC     = "AppIconMac"        # le Mac, dans Resources/Media.xcassets
# **Les deux liseuses, et pas seulement celle du téléphone.**
#
# Le Mac partageait l'icône du dépôt sans jamais la déclarer : sa cible
# n'existait pas quand ce script a été écrit, et rien ne l'a signalé — une app
# sans icône se lance très bien, elle est simplement grise dans le Dock.
TARGET_NAMES = %w[ONT ONTMac]
CIBLE_MAC    = "ONTMac"

abort "✗ #{PROJECT_PATH} introuvable — lancer xcodegen d'abord." unless File.exist?(PROJECT_PATH)

icon_path = File.join(ROOT, "app", ICON_NAME)
abort "✗ #{icon_path} introuvable." unless File.exist?(icon_path)

project = Xcodeproj::Project.open(PROJECT_PATH)
cibles = TARGET_NAMES.map do |nom|
  c = project.targets.find { |x| x.name == nom }
  abort "✗ cible « #{nom} » absente de #{PROJECT_PATH}" unless c
  c
end

changed = false

# 1. La référence de fichier, avec le type `wrapper.icon` — c'est lui qui dit
#    à actool qu'il s'agit d'une icône d'app et non d'un dossier quelconque.
file_ref = project.files.find { |f| f.path == ICON_NAME }
if file_ref
  if file_ref.last_known_file_type != "wrapper.icon"
    file_ref.last_known_file_type = "wrapper.icon"
    changed = true
  end
else
  # Le groupe racine du projet est déjà `app/` : le chemin est relatif à lui,
  # sans préfixe — sinon actool cherche `app/app/ONT.icon`.
  file_ref = project.main_group.new_file(ICON_NAME)
  file_ref.last_known_file_type = "wrapper.icon"
  changed = true
end

# 2. La phase de copie des ressources, et le nom de l'icône — chacun la sienne.
#
# **`ONT.icon` est retiré de la cible macOS**, et pas seulement écarté par le
# réglage : `actool` compile *toutes* ses entrées, donc le laisser dans la phase
# de ressources le ferait planter sur Xcode 26.3 même si l'on nomme une autre
# icône. Le réglage dit quoi composer ; la phase dit quoi lire.
cibles.each do |target|
  mac = target.name == CIBLE_MAC
  phase = target.resources_build_phase
  present = phase.files_references.include?(file_ref)

  if mac && present
    phase.remove_file_reference(file_ref)
    changed = true
  elsif !mac && !present
    phase.add_file_reference(file_ref)
    changed = true
  end

  # 3. Le réglage qu'actool lit pour savoir quelle icône composer.
  voulu = mac ? ICON_MAC : "ONT"
  target.build_configurations.each do |config|
    next if config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] == voulu
    config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = voulu
    changed = true
  end
end

if changed
  project.save
  puts "✓ icônes déclarées — « #{ICON_NAME} » sur ONT, « #{ICON_MAC} » sur #{CIBLE_MAC}"
else
  puts "· icône déjà déclarée"
end
