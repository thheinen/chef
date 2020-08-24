# Author:: Bryan McLellan <btm@loftninjas.org>
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

require "chef-config/mixin/credentials"
require "train"
require_relative "dist"

class Chef
  class TrainTransport
    extend ChefConfig::Mixin::Credentials

    def self.build_transport(logger = Chef::Log.with_child(subsystem: "transport"))
      return nil unless Chef::Config.target_mode?

      # TODO: Consider supporting parsing the protocol from a URI passed to `--target`
      #
      train_config = {}

      # Load the target_mode config context from Chef::Config, and place any valid settings into the train configuration
      tm_config = Chef::Config.target_mode
      protocol = tm_config.protocol
      train_config = tm_config.to_hash.select { |k| Train.options(protocol).key?(k) }
      Chef::Log.trace("Using target mode options from #{Chef::Dist::PRODUCT} config file: #{train_config.keys.join(", ")}") if train_config

      # Load the credentials file, and place any valid settings into the train configuration
      credentials = load_credentials(tm_config.host)
      if credentials
        valid_settings = credentials.select { |k| Train.options(protocol).key?(k) }
        valid_settings[:enable_password] = credentials[:enable_password] if credentials.key?(:enable_password)
        train_config.merge!(valid_settings)
        Chef::Log.trace("Using target mode options from credentials file: #{valid_settings.keys.join(", ")}") if valid_settings
      end

      train_config[:logger] = logger

      # Train handles connection retries for us
      Train.create(protocol, train_config)
    rescue SocketError => e # likely a dns failure, not caught by train
      e.message.replace "Error connecting to #{train_config[:target]} - #{e.message}"
      raise e
    rescue Train::PluginLoadError
      logger.error("Invalid target mode protocol: #{protocol}")
      exit(false)
    end
  end
end
