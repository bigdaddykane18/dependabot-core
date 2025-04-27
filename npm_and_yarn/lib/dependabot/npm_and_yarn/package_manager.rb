# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/version_selector"

module Dependabot
  module NpmAndYarn
    class PackageManager
      extend T::Sig
      extend T::Helpers
      def initialize(package_json, lockfiles:)
        @package_json = package_json
        @lockfiles = lockfiles
        @package_manager = package_json.fetch("packageManager", nil)
        @engines = package_json.fetch("engines", nil)
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def setup(name)
        # we prioritize version mentioned in "packageManager" instead of "engines"
        # i.e. if { engines : "pnpm" : "6" } and { packageManager: "pnpm@6.0.2" },
        # we go for the specificity mentioned in packageManager (6.0.2)

        unless @package_manager&.start_with?("#{name}@") || (@package_manager&.==name.to_s) || @package_manager.nil?
          return
        end

        if @engines && @package_manager.nil?
          # if "packageManager" doesn't exists in manifest file,
          # we check if we can extract "engines" information
          version = check_engine_version(name)

        elsif @package_manager&.==name.to_s
          # if "packageManager" is found but no version is specified (i.e. pnpm@1.2.3),
          # we check if we can get "engines" info to override default version
          version = check_engine_version(name) if @engines

        elsif @package_manager&.start_with?("#{name}@")
          # if "packageManager" info has version specification i.e. yarn@3.3.1
          # we go with the version in "packageManager"
          Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\". Skipped checking \"engines\".")
        end

        version ||= requested_version(name)

        if version
          raise_if_unsupported!(name, version)

          install(name, version)
        else
          version = guessed_version(name)

          if version
            raise_if_unsupported!(name, version.to_s)

            install(name, version) if name == "pnpm"
          end
        end

        version
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      private

      def raise_if_unsupported!(name, version)
        return unless name == "pnpm"
        return unless Version.new(version) < Version.new("7")

        raise ToolVersionNotSupported.new("PNPM", version, "7.*, 8.*")
      end

      def install(name, version)
        Dependabot.logger.info("Installing \"#{name}@#{version}\"")

        SharedHelpers.run_shell_command(
          "corepack install #{name}@#{version} --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only"
        )
      end

      def requested_version(name)
        return unless @package_manager

        match = @package_manager.match(/^#{name}@(?<version>\d+.\d+.\d+)/)
        return unless match

        Dependabot.logger.info("Requested version #{match['version']}")
        match["version"]
      end

      def guessed_version(name)
        lockfile = @lockfiles[name.to_sym]
        return unless lockfile

        version = Helpers.send(:"#{name}_version_numeric", lockfile)

        Dependabot.logger.info("Guessed version info \"#{name}\" : \"#{version}\"")

        version
      end

      sig { params(name: T.untyped).returns(T.nilable(String)) }
      def check_engine_version(name)
        version_selector = VersionSelector.new
        engine_versions = version_selector.setup(@package_json, name)

        return if engine_versions.empty?

        version = engine_versions[name]
        Dependabot.logger.info("Returned (engines) info \"#{name}\" : \"#{version}\"")
        version
      end
    end
  end
end
