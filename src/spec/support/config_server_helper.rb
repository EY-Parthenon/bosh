require 'net/http'
require 'json'

module Bosh::Spec
  class ConfigServerHelper
    def initialize(sandbox, logger)
      @logger = logger
      @port = sandbox.port_provider.get_port(:config_server_port)
      @uaa_config_hash = {
          'client_id' => sandbox.director_config.config_server_uaa_client_id,
          'client_secret' => sandbox.director_config.config_server_uaa_client_secret,
          'url' => sandbox.director_config.config_server_uaa_url,
          'ca_cert_path' => sandbox.director_config.config_server_uaa_ca_cert_path
      }
    end

    def post(name, type)
      json_body = { "name": name, "type": type}
      if type == "root-certificate"
        json_body = {"name": name,"type": "certificate","parameters":{"is_ca": true, "common_name": "#{name}-cn", "alternative_names":["#{name}-an"]}}
      end
      response = send_request('POST', build_uri, JSON.dump(json_body))
      raise "Config server responded with an error.\n #{response.inspect}" unless response.kind_of? Net::HTTPSuccess

      JSON.parse(response.body)
    end

    def put_value(name, value)
      response = send_request('PUT', build_uri, JSON.dump({name: name, value: value}))
      raise "Config server responded with an error.\n #{response.inspect}" unless response.kind_of? Net::HTTPSuccess
    end

    def get_value(name)
      config_server_url = build_uri
      config_server_url.query = URI.escape("name=#{name}")

      response = send_request('GET', config_server_url, nil)
      raise "Config server responded with an error.\n #{response.inspect}" unless response.kind_of? Net::HTTPSuccess
      JSON.parse(response.body)['data'][0]['value']
    end

    def get_second_value(name)
      config_server_url = build_uri
      config_server_url.query = URI.escape("name=#{name}")

      response = send_request('GET', config_server_url, nil)
      raise "Config server responded with an error.\n #{response.inspect}" unless response.kind_of? Net::HTTPSuccess
      body = JSON.parse(response.body)
      body['data'][1]['value']
    end

    def regenerate_certificate(name, body = nil)
      uri = URI.join(base_uri, URI.escape("v1/certificates?name=#{name}"))
      result = send_request('GET', uri, nil)
      result_body = JSON.parse(result.body)

      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      id = result_body['certificates'][0]['id']
      uri = URI.join(base_uri, URI.escape("v1/certificates/#{id}/regenerate"))
      result = send_request('POST', uri, body)
      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      result
    end

    def update_transitional_certificate(name)
      uri = URI.join(base_uri, URI.escape("v1/certificates?name=#{name}"))
      result = send_request('GET', uri, nil)
      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      name_id = JSON.parse(result.body)['certificates'][0]['id']

      config_server_url = build_uri
      config_server_url.query = URI.escape("name=#{name}")

      response = send_request('GET', config_server_url, nil)
      raise "Config server responded with an error.\n #{response.inspect}" unless response.kind_of? Net::HTTPSuccess
      real = JSON.parse(response.body)['data']
      version_id = real[0]['id']
      version_id = real[1]['id'] if real[0]['transitional']

      uri = URI.join(base_uri, URI.escape("v1/certificates/#{name_id}/update_transitional_version"))
      body = '{"version": "' + version_id + '"}'
      result = send_request('PUT', uri, body)
      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      result
    end

    def remove_transitional_certificate(name)
      uri = URI.join(base_uri, URI.escape("v1/certificates?name=#{name}"))
      result = send_request('GET', uri, nil)
      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      name_id = JSON.parse(result.body)['certificates'][0]['id']

      uri = URI.join(base_uri, URI.escape("v1/certificates/#{name_id}/update_transitional_version"))
      body = '{"version": null}'
      result = send_request('PUT', uri, body)
      raise "Config server responded with an error.\n #{result.inspect}" unless result.kind_of? Net::HTTPSuccess
      result
    end


    def send_request(verb, url, body)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ca_file = Bosh::Dev::Sandbox::ConfigServerService::ROOT_CERT
      http.send_request(verb, url.request_uri, body, {'Authorization' => auth_header, 'Content-Type' => 'application/json'})
    end

    def auth_header
      auth_provider = Bosh::Director::ConfigServer::UAAAuthProvider.new(@uaa_config_hash, logger)
      ex = nil

      20.times do
        begin
          return auth_provider.get_token.auth_header
        rescue => ex
          sleep(5)
        end
      end

      raise "Could not obtain UAA token: #{ex.inspect}"
    end

    def logger
      @logger ||= Bosh::Director::Config.logger
    end

    def build_uri
      URI.join(base_uri, "v1/data")
    end

    def base_uri
      URI("http://127.0.0.1:#{@port}/")
    end
  end
end
