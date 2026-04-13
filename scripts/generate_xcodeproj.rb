#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

module OpenBoringBarProjectGenerator
    PROJECT_NAME = 'OpenBoringBar'
    PROJECT_PATH = File.expand_path("../#{PROJECT_NAME}.xcodeproj", __dir__)
    INFO_PLIST_PATH = 'OpenBoringBar/Resources/Info.plist'
    SOURCE_FILES = [
        'OpenBoringBar/App/OpenBoringBarApp.swift',
        'OpenBoringBar/App/MainWindowView.swift',
        'OpenBoringBar/Core/Bar/BarManager.swift'
    ].freeze

    module_function

    def ensure!
        return if File.exist?(PROJECT_PATH)

        project = Xcodeproj::Project.new(PROJECT_PATH)
        target = project.new_target(:application, PROJECT_NAME, :osx, '14.0')

        SOURCE_FILES.each do |relative_path|
            file_ref = project.main_group.new_file(relative_path)
            target.add_file_references([file_ref])
        end

        target.build_configurations.each do |config|
            config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.openboringbar.app'
            config.build_settings['SWIFT_VERSION'] = '5.0'
            config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
            config.build_settings['INFOPLIST_FILE'] = INFO_PLIST_PATH
            config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
            config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
            config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
        end

        project.root_object.attributes['LastUpgradeCheck'] = '1600'
        project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
        project.save
    end
end

OpenBoringBarProjectGenerator.ensure! if $PROGRAM_NAME == __FILE__
