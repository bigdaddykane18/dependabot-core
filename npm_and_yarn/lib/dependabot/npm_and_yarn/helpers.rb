# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    module Helpers
      extend T::Sig

      YARN_PATH_NOT_FOUND =
        /^.*(?<error>The "yarn-path" option has been set \(in [^)]+\), but the specified location doesn't exist)/

      # NPM Version Constants
      NPM_V8 = 8
      NPM_V6 = 6
      NPM_DEFAULT_VERSION = NPM_V8

      # PNPM Version Constants
      PNPM_V9 = 9
      PNPM_V8 = 8
      PNPM_V7 = 7
      PNPM_V6 = 6
      PNPM_DEFAULT_VERSION = PNPM_V9
      PNPM_FALLBACK_VERSION = PNPM_V6

      # YARN Version Constants
      YARN_V3 = 3
      YARN_V2 = 2
      YARN_V1 = 1
      YARN_DEFAULT_VERSION = YARN_V3
      YARN_FALLBACK_VERSION = YARN_V1

      # Determines the npm version depends to the feature flag
      # If the feature flag is enabled, we are going to use the minimum version npm 8
      # Otherwise, we are going to use old versionining npm 6
      sig { params(lockfile: DependencyFile).returns(Integer) }
      def self.npm_version_numeric(lockfile)
        fallback_version_npm8 = Dependabot::Experiments.enabled?(:npm_fallback_version_above_v6)

        return npm_version_numeric_npm8_or_higher(lockfile) if fallback_version_npm8

        npm_version_numeric_npm6_or_higher(lockfile)
      end

      sig { params(lockfile: DependencyFile).returns(Integer) }
      def self.npm_version_numeric_npm6_or_higher(lockfile)
        lockfile_content = T.must(lockfile.content)
        return NPM_V8 if JSON.parse(lockfile_content)["lockfileVersion"].to_i >= 2

        NPM_V6
      rescue JSON::ParserError
        NPM_V6
      end

      # Determines the npm version based on the lockfile version
      # - NPM 7 uses lockfileVersion 2
      # - NPM 8 uses lockfileVersion 2
      # - NPM 9 uses lockfileVersion 3
      sig { params(lockfile: DependencyFile).returns(Integer) }
      def self.npm_version_numeric_npm8_or_higher(lockfile)
        lockfile_content = lockfile.content

        # Return default NPM version if there's no lockfile or it's empty
        return NPM_DEFAULT_VERSION if lockfile_content.nil? || lockfile_content.strip.empty?

        parsed_lockfile = JSON.parse(lockfile_content)

        lockfile_version_str = parsed_lockfile["lockfileVersion"]

        # Default to npm default version if lockfileVersion is missing or empty
        return NPM_DEFAULT_VERSION if lockfile_version_str.nil? || lockfile_version_str.to_s.strip.empty?

        lockfile_version = lockfile_version_str.to_i

        # Using npm 8 as the default for lockfile_version > 2.
        # Update needed to support npm 9+ based on lockfile version.
        return NPM_V8 if lockfile_version >= 2

        NPM_DEFAULT_VERSION
      rescue JSON::ParserError
        NPM_DEFAULT_VERSION # Fallback to default npm version if parsing fails
      end

      sig { params(yarn_lock: DependencyFile).returns(Integer) }
      def self.yarn_version_numeric(yarn_lock)
        if yarn_berry?(yarn_lock)
          YARN_DEFAULT_VERSION
        else
          YARN_FALLBACK_VERSION
        end
      end

      # Mapping from lockfile versions to PNPM versions is at
      # https://github.com/pnpm/spec/tree/274ff02de23376ad59773a9f25ecfedd03a41f64/lockfile, but simplify it for now.

      sig { params(pnpm_lock: DependencyFile).returns(Integer) }
      def self.pnpm_version_numeric(pnpm_lock)
        pnpm_lockfile_version = pnpm_lockfile_version(pnpm_lock).to_f
        return PNPM_V9 if pnpm_lockfile_version >= 9.0
        return PNPM_V8 if pnpm_lockfile_version >= 6.0
        return PNPM_V7 if pnpm_lockfile_version >= 5.4

        PNPM_FALLBACK_VERSION
      end

      def self.fetch_yarnrc_yml_value(key, default_value)
        if File.exist?(".yarnrc.yml") && (yarnrc = YAML.load_file(".yarnrc.yml"))
          yarnrc.fetch(key, default_value)
        else
          default_value
        end
      end

      sig { params(package_lock: T.nilable(DependencyFile)).returns(T::Boolean) }
      def self.npm8?(package_lock)
        return true unless package_lock

        npm_version_numeric(package_lock) == NPM_V8
      end

      sig { params(yarn_lock: T.nilable(DependencyFile)).returns(T::Boolean) }
      def self.yarn_berry?(yarn_lock)
        return false if yarn_lock.nil? || yarn_lock.content.nil?

        yaml = YAML.safe_load(T.must(yarn_lock.content))
        yaml.key?("__metadata")
      rescue StandardError
        false
      end

      sig { returns(Integer) }
      def self.yarn_major_version
        retries = 0
        output = run_single_yarn_command("--version")
        Version.new(output).major
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        # Should never happen, can probably be removed once this settles
        raise "Failed to replace ENV, not sure why" if T.must(retries).positive?

        message = e.message

        missing_env_var_regex = %r{Environment variable not found \((?:[^)]+)\) in #{Dir.pwd}/(?<path>\S+)}

        if message.match?(missing_env_var_regex)
          match = T.must(message.match(missing_env_var_regex))
          path = T.must(match.named_captures["path"])

          File.write(path, File.read(path).gsub(/\$\{[^}-]+\}/, ""))
          retries = T.must(retries) + 1

          retry
        end

        handle_subprocess_failure(e)
      end

      def self.handle_subprocess_failure(error)
        message = error.message
        if YARN_PATH_NOT_FOUND.match?(message)
          error = T.must(T.must(YARN_PATH_NOT_FOUND.match(message))[:error]).sub(Dir.pwd, ".")
          raise MisconfiguredTooling.new("Yarn", error)
        end

        if message.include?("Internal Error") && message.include?(".yarnrc.yml")
          raise MisconfiguredTooling.new("Invalid .yarnrc.yml file", message)
        end

        raise
      end

      sig { returns(T::Boolean) }
      def self.yarn_zero_install?
        File.exist?(".pnp.cjs")
      end

      sig { returns(T::Boolean) }
      def self.yarn_offline_cache?
        yarn_cache_dir = fetch_yarnrc_yml_value("cacheFolder", ".yarn/cache")
        File.exist?(yarn_cache_dir) && (fetch_yarnrc_yml_value("nodeLinker", "") == "node-modules")
      end

      sig { returns(String) }
      def self.yarn_berry_args
        if yarn_major_version == 2
          ""
        elsif yarn_berry_skip_build?
          "--mode=skip-build"
        else
          # We only want this mode if the cache is not being updated/managed
          # as this improperly leaves old versions in the cache
          "--mode=update-lockfile"
        end
      end

      sig { returns(T::Boolean) }
      def self.yarn_berry_skip_build?
        yarn_major_version >= YARN_V3 && (yarn_zero_install? || yarn_offline_cache?)
      end

      sig { returns(T::Boolean) }
      def self.yarn_berry_disable_scripts?
        yarn_major_version == YARN_V2 || !yarn_zero_install?
      end

      sig { returns(T::Boolean) }
      def self.yarn_4_or_higher?
        yarn_major_version >= 4
      end

      def self.setup_yarn_berry
        # Always disable immutable installs so yarn's CI detection doesn't prevent updates.
        run_single_yarn_command("config set enableImmutableInstalls false")
        # Do not generate a cache if offline cache disabled. Otherwise side effects may confuse further checks
        run_single_yarn_command("config set enableGlobalCache true") unless yarn_berry_skip_build?
        # We never want to execute postinstall scripts, either set this config or mode=skip-build must be set
        run_single_yarn_command("config set enableScripts false") if yarn_berry_disable_scripts?
        if (http_proxy = ENV.fetch("HTTP_PROXY", false))
          run_single_yarn_command("config set httpProxy #{http_proxy}", fingerprint: "config set httpProxy <proxy>")
        end
        if (https_proxy = ENV.fetch("HTTPS_PROXY", false))
          run_single_yarn_command("config set httpsProxy #{https_proxy}", fingerprint: "config set httpsProxy <proxy>")
        end
        return unless (ca_file_path = ENV.fetch("NODE_EXTRA_CA_CERTS", false))

        if yarn_4_or_higher?
          run_single_yarn_command("config set httpsCaFilePath #{ca_file_path}")
        else
          run_single_yarn_command("config set caFilePath #{ca_file_path}")
        end
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        setup_yarn_berry
        commands.each { |cmd, fingerprint| run_single_yarn_command(cmd, fingerprint: fingerprint) }
      end

      # Run single npm command returning stdout/stderr.
      #
      # NOTE: Needs to be explicitly run through corepack to respect the
      # `packageManager` setting in `package.json`, because corepack does not
      # add shims for NPM.
      def self.run_npm_command(command, fingerprint: command)
        SharedHelpers.run_shell_command("corepack npm #{command}", fingerprint: "corepack npm #{fingerprint}")
      end

      # Setup yarn and run a single yarn command returning stdout/stderr
      def self.run_yarn_command(command, fingerprint: nil)
        setup_yarn_berry
        run_single_yarn_command(command, fingerprint: fingerprint)
      end

      # Run single pnpm command returning stdout/stderr
      def self.run_pnpm_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command("pnpm #{command}", fingerprint: "pnpm #{fingerprint || command}")
      end

      # Run single yarn command returning stdout/stderr
      def self.run_single_yarn_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command("yarn #{command}", fingerprint: "yarn #{fingerprint || command}")
      end
      private_class_method :run_single_yarn_command

      def self.pnpm_lockfile_version(pnpm_lock)
        pnpm_lock.content.match(/^lockfileVersion: ['"]?(?<version>[\d.]+)/)[:version]
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).returns(T::Array[Dependency]) }
      def self.dependencies_with_all_versions_metadata(dependency_set)
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
