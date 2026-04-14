#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'xcodeproj'

module OpenBoringBarProjectGenerator
    PROJECT_NAME = 'OpenBoringBar'
    ROOT_PATH = File.expand_path('..', __dir__)
    PROJECT_PATH = File.expand_path("../#{PROJECT_NAME}.xcodeproj", __dir__)
    INFO_PLIST_PATH = 'OpenBoringBar/Resources/Info.plist'
    SOURCE_GLOBS = [
        'OpenBoringBar/App/**/*.swift',
        'OpenBoringBar/Core/**/*.swift'
    ].freeze
    RESOURCE_GLOBS = [
        'OpenBoringBar/Resources/**/*.xcassets'
    ].freeze

    module_function

    def ensure!
        FileUtils.rm_rf(PROJECT_PATH) if File.exist?(PROJECT_PATH)

        project = Xcodeproj::Project.new(PROJECT_PATH)
        target = project.new_target(:application, PROJECT_NAME, :osx, '14.0')

        source_files.each do |relative_path|
            group = group_for_file_path(project.main_group, relative_path)
            file_ref = group.new_file(File.basename(relative_path))
            target.add_file_references([file_ref])
        end

        resource_files.each do |relative_path|
            group = group_for_file_path(project.main_group, relative_path)
            file_ref = group.new_file(File.basename(relative_path))
            target.resources_build_phase.add_file_reference(file_ref, true)
        end

        target.build_configurations.each do |config|
            config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.openboringbar.app'
            config.build_settings['SWIFT_VERSION'] = '5.0'
            config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
            config.build_settings['INFOPLIST_FILE'] = INFO_PLIST_PATH
            config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
            config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
            config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
            config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
        end

        project.root_object.attributes['LastUpgradeCheck'] = '1600'
        project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
        project.save
    end

    def source_files
        SOURCE_GLOBS
            .flat_map { |pattern| Dir.glob(File.join(ROOT_PATH, pattern)) }
            .select { |path| File.file?(path) }
            .sort
            .map { |path| Pathname.new(path).relative_path_from(Pathname.new(ROOT_PATH)).to_s }
    end

    def resource_files
        RESOURCE_GLOBS
            .flat_map { |pattern| Dir.glob(File.join(ROOT_PATH, pattern)) }
            .select { |path| File.directory?(path) }
            .sort
            .map { |path| Pathname.new(path).relative_path_from(Pathname.new(ROOT_PATH)).to_s }
    end

    def group_for_file_path(root_group, relative_path)
        directory = File.dirname(relative_path)
        return root_group if directory == '.'

        directory
            .split(File::SEPARATOR)
            .reduce(root_group) do |parent_group, path_component|
                parent_group.groups.find { |group| group.display_name == path_component } ||
                    parent_group.new_group(path_component, path_component)
            end
    end
end

OpenBoringBarProjectGenerator.ensure! if $PROGRAM_NAME == __FILE__
