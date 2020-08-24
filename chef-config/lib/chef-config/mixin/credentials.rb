#
# Copyright:: Copyright (c) Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "tomlrb"
require "vault"
require_relative "../path_helper"

module ChefConfig
  module Mixin
    # Helper methods for working with credentials files.
    #
    # @since 13.7
    # @api internal
    module Credentials
      # Compute the active credentials profile name.
      #
      # The lookup order is argument (from --profile), environment variable
      # ($CHEF_PROFILE), context file (~/.chef/context), and then "default" as
      # a fallback.
      #
      # @since 14.4
      # @param profile [String, nil] Optional override for the active profile,
      #   normally set via a command-line option.
      # @return [String]
      def credentials_profile(profile = nil)
        context_file = PathHelper.home(ChefConfig::Dist::USER_CONF_DIR, "context").freeze
        if !profile.nil?
          profile
        elsif ENV.include?("CHEF_PROFILE")
          ENV["CHEF_PROFILE"]
        elsif File.file?(context_file)
          File.read(context_file).strip
        else
          "default"
        end
      end

      # Load and process the active credentials.
      #
      # @see WorkstationConfigLoader#apply_credentials
      # @param profile [String, nil] Optional override for the active profile,
      #   normally set via a command-line option.
      # @return [void]
      def load_credentials(profile = nil)
        type = Chef::Config[:credentials].type

        method = "load_credentials_#{type}"
        if Credentials.method_defined?(method)
          send(method.to_sym, profile)
        else
          raise ChefConfig::ConfigurationError, "Credentials type #{type} not known."
        end
      end

      # List profiles available
      #
      # @return [Array<String>]
      def list_profiles
        type = Chef::Config[:credentials].type
        method = "list_profiles_#{type}"

        send(method.to_sym) if Credentials.method_defined?(method)
      end

      # Get all credential data available.
      #
      # @return [Hash]
      def parse_credentials
        type = Chef::Config[:credentials].type
        method = "parse_credentials_#{type}"

        send(method.to_sym) if Credentials.method_defined?(method)
      end

      private

      # Compute the path to the credentials file.
      #
      # @since 14.4
      # @return [String]
      def credentials_file_path
        Chef::Config[:credentials][:path] || PathHelper.home(ChefConfig::Dist::USER_CONF_DIR, "credentials").freeze
      end

      # Load and parse the credentials file.
      #
      # Returns `nil` if the credentials file is unavailable.
      #
      # @since 14.4
      # @return [String, nil]
      def parse_credentials_file
        credentials_file = credentials_file_path
        return nil unless File.file?(credentials_file)

        begin
          Tomlrb.load_file(credentials_file)
        rescue => e
          # TOML's error messages are mostly rubbish, so we'll just give a generic one
          message = "Unable to parse Credentials file: #{credentials_file}\n"
          message << e.message
          raise ChefConfig::ConfigurationError, message
        end
      end

      # Load and process the active credentials from file.
      #
      # @param profile [String, nil] Optional override for the active profile,
      #   normally set via a command-line option.
      # @return [void]
      def load_credentials_file(profile = nil)
        profile = credentials_profile(profile)
        config = parse_credentials_file
        return if config.nil? # No credentials, nothing to do here.

        if config[profile].nil?
          # Unknown profile name. For "default" just silently ignore, otherwise
          # raise an error.
          return if profile == "default"

          raise ChefConfig::ConfigurationError, "Profile #{profile} doesn't exist. Please add it to #{credentials_file_path}."
        end

        config[profile].map { |k, v| [k.to_sym, v] }.to_h
      end

      # List profiles in credentials file.
      #
      # @return [Array<String>]
      def list_profiles_file
        parse_credentials_file.keys
      end

      # Load and process the active credentials from Hashicorp Vault.
      #
      # @param profile [String, nil] Optional override for the active profile,
      #   normally set via a command-line option.
      # @return [void]
      def load_credentials_vault(profile = nil)
        basepath = Chef::Config[:credentials].basepath

        credentials = vault_document("#{basepath}/#{profile}")
        raise ChefConfig::ConfigurationError, "Profile '#{profile}' has no credentials in Vault at '#{basepath}/#{profile}'." unless credentials

        credentials
      end

      # List profiles in Hashicorp Vault.
      #
      # @return [Array<String>]
      def list_profiles_vault
        basepath = Chef::Config[:credentials].basepath

        vault_subkeys(basepath)
      end

      def parse_credentials_vault
        credentials = {}

        list_profiles_vault.each do |profile|
          credentials[profile] = load_credentials_vault(profile)
        end

        credentials
      end

      def vault
        return @vault unless @vault.nil?

        @vault = Vault::Client.new(address: Chef::Config[:credentials].address)
        @vault.token = Chef::Config[:credentials].token

        @vault
      end

      def vault_document(path)
        engine = vault_engine(path)
        document = vault_path(path)

        result = vault.kv(engine).read(document)
        result&.data
      end

      def vault_subkeys(path)
        engine = vault_engine(path)
        document = vault_path(path)

        vault.kv(engine).list(document)
      end

      def vault_engine(path)
        path.split('/').first
      end

      def vault_path(path)
        path.split('/').slice(1..-1).join('/')
      end
    end
  end
end
