#!/usr/bin/env ruby
# add_xcframework_to_xcode.rb
# Ajoute chabaka_engine.xcframework au target Runner avec Embed & Sign.
# À exécuter APRÈS build_ios.sh, AVANT flutter build ios.
#
# Usage :
#   ruby tools/build-rust/add_xcframework_to_xcode.rb
#
# Pré-requis : gem xcodeproj (fourni avec CocoaPods)

require 'xcodeproj'
require 'pathname'

REPO_ROOT      = Pathname.new(__FILE__).dirname.parent.parent.realpath
XCODEPROJ_PATH = REPO_ROOT / 'ios' / 'Runner.xcodeproj'
XCFW_PATH      = REPO_ROOT / 'ios' / 'Frameworks' / 'chabaka_engine.xcframework'
TARGET_NAME    = 'Runner'
XCFW_REL       = XCFW_PATH.relative_path_from(REPO_ROOT / 'ios').to_s

unless XCFW_PATH.exist?
  abort "[add_xcframework] ERREUR : #{XCFW_PATH} introuvable.\n" \
        "Générez d'abord : ./tools/build-rust/build_ios.sh"
end

project = Xcodeproj::Project.open(XCODEPROJ_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "[add_xcframework] Target '#{TARGET_NAME}' introuvable dans le projet." unless target

# Cherche ou crée le groupe Frameworks dans le projet
frameworks_group = project.groups.find { |g| g.display_name == 'Frameworks' } ||
                   project.new_group('Frameworks')

# Vérifie si le xcframework est déjà référencé
already_ref = project.files.any? { |f| f.path&.end_with?('chabaka_engine.xcframework') }

if already_ref
  puts "[add_xcframework] chabaka_engine.xcframework déjà référencé dans le projet."
else
  # Ajoute la référence fichier
  file_ref = frameworks_group.new_file(XCFW_REL, :group)
  file_ref.name            = 'chabaka_engine.xcframework'
  file_ref.last_known_file_type = 'wrapper.xcframework'
  file_ref.source_tree     = 'SOURCE_ROOT'

  # Ajoute au "Link Binary With Libraries" de chaque configuration
  target.frameworks_build_phase.add_file_reference(file_ref)
  puts "[add_xcframework] Ajouté à la phase Link Binary With Libraries."

  # Ajoute à "Embed Frameworks" (Embed & Sign)
  embed_phase = target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.name == 'Embed Frameworks' }
  unless embed_phase
    embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
    embed_phase.name        = 'Embed Frameworks'
    embed_phase.dst_path    = ''
    embed_phase.dst_subfolder_spec = '10'  # Frameworks
    target.build_phases << embed_phase
    puts "[add_xcframework] Phase 'Embed Frameworks' créée."
  end

  embed_ref = embed_phase.add_file_reference(file_ref)
  embed_ref.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
  puts "[add_xcframework] Ajouté à 'Embed Frameworks' avec CodeSignOnCopy."
end

project.save
puts "[add_xcframework] Runner.xcodeproj sauvegardé."
puts "[add_xcframework] Prochain : cd ios && pod install"
