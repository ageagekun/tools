require 'net/https'
require "uri"
require "cgi"
require 'openssl'
require 'base64'

module IIJAPI
  class Base
    attr_accessor :method, :request_path, :uri

    def self.execute!(*args)
      request  = self.new(*args)
      response = request.execute!
      self.scan_response(response)
    end

    def self.scan_response(response)
      parsed_response = JSON.parse(response.body)
      raise "ERROR!:#{response.code}\n #{parsed_response}" unless response.code_type == Net::HTTPOK
      raise "ERROR!:#{parsed_response["ErrorResponse"]}" unless parsed_response["ErrorResponse"].nil?
      return parsed_response
    end

    def initialize(method, request_path, options={})
      self.method = method
      self.request_path = request_path
      self.config.merge(options).each do |key, value|
        instance_variable_set("@#{key}", value)
        self.class.send(:attr_reader, key)
      end
    end

    def execute!
      self.uri = URI.parse [self.base_url, "r", self.api_version, self.service_code, self.request_path].join("/")
      http_base = Net::HTTP.new(self.uri.host, self.uri.port)
      http_base.use_ssl = true
      http_base.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = "Net::HTTP::#{self.method.capitalize}".constantize.new(self.uri.request_uri, self.header_options)
      http_base.request(request)
    end

    def config
      {
        :base_url     => "https://do.api.iij.jp",
        :access_key   => "", # Enter your information
        :secret_key   => "", # Enter your information
        :service_code => "", # Enter your information
        :api_version  => "20140601",
        :signature_method  => "HmacSHA256",
        :signature_version => "2",
      }
    end

    def base_header_options
      {
       "x-iijapi-Expire" => (Time.now + 5.hours).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "x-iijapi-SignatureMethod"  => self.signature_method,
       "x-iijapi-SignatureVersion" => self.signature_version,
      }
    end

    def signature
      Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, self.secret_key, self.sign_string)).strip()
    end

    def header_options
      self.base_header_options.merge({"Authorization" => "IIJAPI #{self.access_key}:#{self.signature}"})
    end

    def shaped_request_header
      self.base_header_options.map{|key,value| "#{key.downcase}:#{value}"}.join("\n")
    end

    def sign_string
      [self.method, "", "", self.shaped_request_header, self.uri.request_uri].join("\n")
    end
  end

  class GetRecords < IIJAPI::Base
    def self.execute!(*args)
      zone = args.shift
      options = args.extract_options!
      records = super("GET", "#{zone}/records/RELATIVE.json", options)
      self.put_backup!("#{zone}.conf", records["Text"])
    end

    def self.put_backup!(filename, records)
      File.open(filename, 'w') {|file| file.write records}
    end
  end

  class GetZones < IIJAPI::Base
    def self.execute!(*args)
      options = args.extract_options!
      zones = super("GET", "zones.json", options)
      return zones["ZoneList"].to_a
    end
  end
end

IIJAPI::GetZones.execute!(nil).sort.each do |zone|
  IIJAPI::GetRecords.execute!(CGI.escape(zone))
end
