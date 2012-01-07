#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'bundler/setup'
require 'goliath'
require 'net/yail'
require 'yaml'

module Net
  class YAIL
    def report(*lines)
      # 出力うざい
      #lines.each {|line| $stdout.puts "(#{Time.now.strftime('%H:%M.%S')}) #{line}"}
    end
  end
end

module MetroTransit
  module IRC
    class << self
      def settings
        @settings ||= YAML.load(File.open(File.expand_path('../config.yml', __FILE__)))
      end

      def client
        unless @client
          @client = Net::YAIL.new(
            :address => settings['host'],
            :port => settings['port'],
            :nicknames => [settings['nick']].flatten,
            :server_password => settings['pass'],
          )
          @client.start_listening
        end
        @client
      end
    end
  end

  module Logger
    class << self
      def setup
        for event in [:msg, :notice, :join]
          IRC.client.before_filter(:"incoming_#{event}", self.method(:store_incoming))
          IRC.client.before_filter(:"outgoing_#{event}", self.method(:store_outgoing))
        end
      end

      private

      def store_incoming(e)
        begin
          puts "#{e.msg.command}: #{e.msg.params.map { |s| s.force_encoding('utf-8') }.join(' ')}"
          #nick = e.prefix rescue e.nick
          #puts "{%s} <%s> %s" % [e.target || e.channel, nick, e.message]
        rescue
          p e
          p e.msg
        end
      end

      def store_outgoing(e)
        begin 
          puts "#{e.type}: {#{e.target}} <#{IRC.client.me}> #{e.message}"
        rescue
          p e
        end
      end
    end
  end

  module API
    class << self
      def setup
        IRC.client.on_join { |e| channels[e.channel] = e }
        IRC.client.on_leave { |e| channels.delete e.channel }
      end

      def channels
        @channels ||= {}
      end
    end

    class Base < Goliath::API
      use Goliath::Rack::Params
      use Goliath::Rack::Render, [:json, :xml]

      def process_request
        {:response => 'OK'}
      end

      def response(env)
        [200, {}, process_request]
      end
    end

    class Update < Base
      use Goliath::Rack::Validation::RequestMethod, 'POST'
      use Goliath::Rack::Validation::RequiredParam, :key => 'text'
      use Goliath::Rack::Validation::RequiredParam, :key => 'target'
      use Goliath::Rack::Validation::BooleanValue, :key => 'notice', :default => false

      def process_request
        method = env.params['notice'] ? IRC.client.method(:notice) : IRC.client.method(:msg)
        method.call(env.params['target'], env.params['text'])
        super
      end
    end

    class Channels < Base
      use Goliath::Rack::Validation::RequestMethod, 'GET'

      def process_request
        {:channels => API.channels.keys}
      end

      def response(env)
        [200, {}, process_request]
      end
    end

    class Routes < Goliath::API
      map '/update', Update
      map '/channels', Channels
    end
  end

  Logger.setup
  API.setup
end
