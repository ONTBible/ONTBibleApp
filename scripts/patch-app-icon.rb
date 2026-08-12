#!/usr/bin/env ruby
# frozen_string_literal: true

# Déclare le bundle Icon Composer (`app/ONT.icon`) comme icône de l'app.
#
# xcodegen ne sait pas écrire le type de fichier `wrapper.icon` dont actool a
# besoin, ni poser `ASSETCATALOG_COMPILER_APPICON_NAME`. On refait donc cette
# passe avec la gemme `xcodeproj` après chaque génération.
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
ICON_NAME    = "ONT.icon"
TARGET_NAME  = "ONT"

abort "✗ #{PROJECT_PATH} introuvable — lancer xcodegen d'abord." unless File.exist?(PROJECT_PATH)

icon_path = File.join(ROOT, "app", ICON_NAME)
abort "✗ #{icon_path} introuvable." unless File.exist?(icon_path)

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "✗ cible « #{TARGET_NAME} » absente de #{PROJECT_PATH}" unless target

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

# 2. La phase de copie des ressources.
phase = target.resources_build_phase
unless phase.files_references.include?(file_ref)
  phase.add_file_reference(file_ref)
  changed = true
end

# 3. Le réglage qui désigne l'icône.
target.build_configurations.each do |config|
  next if config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] == "ONT"

  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "ONT"
  changed = true
end

if changed
  project.save
  puts "✓ icône « #{ICON_NAME} » déclarée"
else
  puts "· icône déjà déclarée"
end
