require "forwardable" unless defined?(Forwardable)

require_relative "../http/simple"
require_relative "train/http"

module TargetIO
  class HTTP
    extend Forwardable
    def_delegators :@http_class, :get, :head, :patch, :post, :put, :delete

    # Only for Chef::Provider::RemoteFile::HTTP
    def_delegators :@http_class, :streaming_request, :streaming_request_with_progress, :last_response

    def initialize(url, http_client_opts = {})
      if ::ChefConfig::Config.target_mode?
        @http_class = TargetIO::TrainCompat::HTTP.new(url, http_client_opts)
      else
        @http_class = Chef::HTTP::Simple.new(url, http_client_opts)
      end
    end
  end
end