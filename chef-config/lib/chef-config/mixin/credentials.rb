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

require "vault"
require_relative "credentials_file"
require_relative "credentials_vault"

module ChefConfig
  module Mixin
    # Helper methods for working with credentials files.
    #
    # @since 13.7
    # @api internal
    module Credentials
      include ChefConfig::Mixin::Credentials::RFCFile
      include ChefConfig::Mixin::Credentials::Vault

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

      # List profiles available
      #
      # @return [Array<String>]
      def list_profiles
        type = Chef::Config[:credentials].type
        method = "list_profiles_#{type}"

        raise ChefConfig::ConfigurationError, "Credentials type #{type} not known." unless Credentials.method_defined?(method)

        send(method.to_sym)
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

        raise ChefConfig::ConfigurationError, "Credentials type #{type} not known." unless Credentials.method_defined?(method)

        send(method.to_sym, profile)
      end

      # Get all credential data available.
      #
      # @return [Hash]
      def parse_credentials
        type = Chef::Config[:credentials].type
        method = "parse_credentials_#{type}"

        raise ChefConfig::ConfigurationError, "Credentials type #{type} not known." unless Credentials.method_defined?(method)

        send(method.to_sym)
      end
    end
  end
end
