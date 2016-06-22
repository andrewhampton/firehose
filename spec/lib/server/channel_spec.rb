require 'spec_helper'

describe Firehose::Server::Channel do
  include EM::TestHelper

  let(:channel_key)     { '/bears/are/mean' }
  let(:channel)         { Firehose::Server::Channel.new(channel_key, redis: Firehose::Server.redis.connection, subscriber: subscriber) }
  let(:subscriber)      { Firehose::Server::Subscriber.new }
  let(:message)         { 'Raaaarrrrrr!!!!' }
  let(:publisher)       { Firehose::Server::Publisher.new }

  def push_message
    redis_exec 'lpush', "firehose:#{channel_key}:list", message
    redis_exec 'set', "firehose:#{channel_key}:sequence", '100'
  end

  context "callbacks" do
    it "calls #on_message" do
      push_message
      em do
        expect(channel).to receive(:on_message).with(Firehose::Server::MessageBuffer::Message.new(message, 100))
        channel.next_messages.callback { em.stop }
      end
    end

    it "calls #on_subscribe" do
      expect_any_instance_of(Firehose::Server::Channel).to receive(:on_subscribe).with({})
      em do
        channel
        em.next_tick { em.stop }
      end
    end

    it "calls #on_unsubscribe" do
      push_message
      em do
        expect(channel).to receive(:on_unsubscribe).once
        channel.next_messages.callback { em.stop }
      end
    end
  end

  describe "#next_messages" do
    it "waits for message if message was not published before subscription" do
      em do
        channel.next_messages.callback do |messages|
          msg = messages.first
          expect(msg.payload).to eql(message)
          expect(msg.sequence).to eql(1)
          em.next_tick { em.stop }
        end

        publisher.publish(channel_key, message)
      end
    end

    it "returns the latest message and sequence if no sequence is given" do
      push_message

      em do
        channel.next_messages.callback do |messages|
          msg = messages.first
          expect(msg.payload).to eql(message)
          expect(msg.sequence).to eql(100)

          # This must happen _after_ the callback runs in order to pass consistently.
          em.next_tick { em.stop }
        end
      end
    end

    it "waits for message if most recent sequence is given" do
      push_message

      em 3 do
        channel.next_messages(100).callback do |messages|
          msg = messages.first.payload
          seq = messages.first.sequence
          expect(msg).to eql(message)
          expect(seq).to eql(101)
          em.next_tick { em.stop }
        end.errback

        publisher.publish(channel_key, message)
      end
    end

    it "waits for message if a future sequence is given" do
      push_message

      em 3 do
        channel.next_messages(101).callback do |messages|
          msg = messages.first.payload
          seq = messages.first.sequence
          expect(msg).to eql(message)
          expect(seq).to eql(101)
          em.next_tick { em.stop }
        end.errback

        publisher.publish(channel_key, message)
      end
    end

    it "immediatly gets a message if message sequence is behind and in list" do
      messages = %w[a b c d e]

      em 3 do
        publish_messages(messages) do
          channel.next_messages(2).callback do |messages|
            msg = messages.first.payload
            seq = messages.first.sequence
            expect(msg).to eql('c')
            expect(seq).to eql(3)

            # This must happen _after_ the callback runs in order to pass consistently.
            em.next_tick { em.stop }
          end
        end
      end
    end

    it "gets current message if sequence is really far behind in list" do
      messages = ('aa'..'zz').to_a

      em 3 do
        publish_messages(messages) do
          channel.next_messages(2).callback do |msgs|
            msg = msgs.last.payload
            seq = msgs.last.sequence
            expect(msg).to eql(messages.last)
            expect(seq).to eql(messages.size)

            # This must happen _after_ the callback runs in order to pass consistently.
            em.next_tick { em.stop }
          end
        end
      end
    end

    context "a timeout is set" do
      it "times out if message isn't published in time" do
        push_message

        em 3 do
          channel.next_messages(100, :timeout => 1).callback do |messages|
            msg = messages.first.payload
            seq = messages.first.sequence
            raise 'test failed'
          end.errback do |e|
            expect(e).to eql(:timeout)
            em.next_tick { em.stop }
          end

          EM::add_timer(2) do
            publisher.publish(channel_key, message)
          end
        end
      end

      it "does not timeout if message is published in time" do
        push_message

        em 3 do
          d = channel.next_messages(100, :timeout => 2).callback do |messages|
            msg = messages.first.payload
            seq = messages.first.sequence
            expect(msg).to eql(message)
            expect(seq).to eql(101)
            EM::add_timer(1) do
              em.stop
            end
          end.errback do |e|
            raise 'test failed'
          end

          d.should_not_receive(:fail)

          EM::add_timer(1) do
            publisher.publish(channel_key, message)
          end
        end
      end
    end
  end


  # Publishes the given messages and executes the given block when finished.
  def publish_messages(all_messages)
    publish = Proc.new do |messages_to_publish|
      msg = messages_to_publish.shift
      publisher.publish(channel_key, msg).callback do
        if messages_to_publish.empty?
          # Publishing is done, proceed with the test
          yield
        else
          # Publish the next message
          publish.call messages_to_publish
        end
      end
    end

    publish.call all_messages.dup
  end
end
