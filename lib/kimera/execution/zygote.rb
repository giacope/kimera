# frozen_string_literal: true

require "json"
require "timeout"
require_relative "child_process"
require_relative "last_words"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Zygote
  include Kimera::Execution::ChildProcess

  SIGNAL = "QUIT"
  FRAMES = 40

  class Died < StandardError
    attr_reader :signal, :code

    def initialize(message, signal: nil, code: nil)
      super(message)
      @signal = signal
      @code = code
    end
  end

  class Raised < StandardError
    attr_reader :kind

    def initialize(kind, message)
      super(message)
      @kind = kind
    end

    def headline = "#{kind}: #{message}"
  end

  Pipe =
    Data.define(:reader, :writer) do
      def post(text)
        reader.close
        writer.write(text)
        writer.close
      end

      def take
        writer.close
        reader.read.tap { reader.close }
      end
    end

  def call(&)
    pipe = Pipe.new(*IO.pipe(Encoding::UTF_8))
    saved = Signal.trap(SIGNAL, "IGNORE")
    collect(pipe, born(pipe, saved, &))
  ensure
    restore(saved)
  end

  private

  def born(pipe, saved, &) = fork { spawned(pipe, saved, &) }

  def spawned(pipe, saved, &)
    restore(saved)
    pipe.post(JSON.generate(outcome(&)))
    exit!(0)
  end

  def collect(pipe, pid) = settle(pipe.take, reap(pid))

  def restore(saved) = Signal.trap(SIGNAL, saved)

  def outcome
    { "value" => yield }
  rescue Timeout::Error, StandardError, ScriptError => error
    { "raised" => error.class.name, "message" => error.message, "frames" => Array(error.backtrace).first(FRAMES) }
  rescue SignalException => error
    last(error)
  end

  def last(error)
    raise(error) if error.is_a?(Interrupt)
    { "died" => Kimera::Execution::LastWords.new(error).to_s, "signal" => error.signo }
  end

  def settle(text, status)
    payload = parse(text) || { "died" => "", "signal" => status&.termsig, "code" => status&.exitstatus }
    raise(Died.new(payload["died"], signal: payload["signal"], code: payload["code"])) if payload.key?("died")
    raise(rebuilt(payload)) if payload.key?("raised")
    payload["value"]
  end

  def rebuilt(payload)
    kind = payload["raised"]
    message = payload["message"]
    error = kind == Timeout::Error.name ? Timeout::Error.new(message) : Raised.new(kind, message)
    error.tap { |rebuilt| rebuilt.set_backtrace(payload["frames"]) if payload["frames"] }
  end
end
