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
  end

  def call(&)
    reader, writer = IO.pipe(Encoding::UTF_8)
    saved = Signal.trap(SIGNAL, "IGNORE")
    collect(born(reader, writer, saved, &), reader, writer)
  ensure
    restore(saved)
  end

  private

  def born(reader, writer, saved, &) = fork || spawned(reader, writer, saved, &)

  def spawned(reader, writer, saved, &)
    reader.close
    restore(saved)
    writer.write(JSON.generate(outcome(&)))
    writer.close
    exit!(0)
  end

  def restore(saved) = Signal.trap(SIGNAL, saved)

  def outcome
    { "value" => yield }
  rescue Timeout::Error, StandardError, ScriptError => error
    { "raised" => error.class.name, "message" => error.message }
  rescue SignalException => error
    last(error)
  end

  def last(error)
    raise(error) if error.is_a?(Interrupt)
    { "died" => Kimera::Execution::LastWords.new(error).to_s, "signal" => error.signo }
  end

  def collect(pid, reader, writer)
    writer.close
    text = reader.read
    reader.close
    settle(text, reap(pid))
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
    kind == Timeout::Error.name ? Timeout::Error.new(message) : Raised.new(kind, message)
  end
end
