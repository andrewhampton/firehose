require 'faye/websocket'
require 'em-hiredis'

# Set the EM::Hiredis logger to be the same as the Firehose logger.
EM::Hiredis.logger = Firehose.logger

module Firehose
  # Firehose components that sit between the Rack HTTP software and the Redis server.
  # This mostly handles message sequencing and different HTTP channel names.
  module Server
    autoload :MessageBuffer,    'firehose/server/message_buffer'
    autoload :Subscriber,       'firehose/server/subscriber'
    autoload :Publisher,        'firehose/server/publisher'
    autoload :Channel,          'firehose/server/channel'
    autoload :App,              'firehose/server/app'
    autoload :Redis,            'firehose/server/redis'
    autoload :Metrics,          'firehose/server/metrics'
    autoload :MetricsCollector, 'firehose/server/metrics_collector'

    def self.redis
      @redis ||= Redis.new
    end

    def self.metrics
      @metrics ||= Firehose::Server::Metrics::TimeSeries.new
    end
  end
end
