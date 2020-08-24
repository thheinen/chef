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

module ChefConfig
  module Mixin
    # Helper methods for working with credentials from Hashicorp Vault.
    #
    # @api internal
    module Credentials
      module Vault

        # List profiles in Hashicorp Vault.
        #
        # @return [Array<String>]
        def list_profiles_vault
          basepath = Chef::Config[:credentials].basepath

          vault_subkeys(basepath)
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

        # Enumerate all available profiles with their settings
        #
        # @return [Hash]
        def parse_credentials_vault
          credentials = {}

          list_profiles_vault.each do |profile|
            credentials[profile] = load_credentials_vault(profile)
          end

          credentials
        end

        private

        def vault
          return @vault unless @vault.nil?

          @vault = ::Vault::Client.new(address: Chef::Config[:credentials].address)
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
end
