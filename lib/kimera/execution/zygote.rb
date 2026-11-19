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
    def initialize(message, signal: nil, code: nil)
      super(message)
      @signal = signal
      @code = code
    end

    def epitaph = message

    def echo(duty) = signal ? duty.die_of(signal) : duty.exit_with(code || 1)

    private

    attr_reader :signal, :code
  end

  class Raised < StandardError
    def initialize(kind, message)
      super(message)
      @kind = kind
    end

    def headline = "#{kind}: #{message}"

    private

    attr_reader :kind
  end

  class Pipe
    def initialize(reader, writer)
      @reader = reader
      @writer = writer
    end

    def post(text)
      reader.close
      writer.write(text)
      writer.close
    end

    def seal = writer.close

    def take
      writer.close
      reader.read.tap { reader.close }
    end

    private

    attr_reader :reader, :writer
  end

  def initialize(exits = Kernel)
    @exits = exits
  end

  def call
    saved = Signal.trap(SIGNAL, "IGNORE")
    hatch do
      restore(saved)
      yield
    end.call
  ensure
    restore(saved)
  end

  def hatch(&)
    pipe = Pipe.new(*IO.pipe(Encoding::UTF_8))
    pid = born(pipe, &)
    pipe.seal
    -> { collect(pipe, pid) }
  end

  private

  def born(pipe, &) = fork { spawned(pipe, &) }

  def spawned(pipe, &)
    pipe.post(JSON.generate(outcome(&)))
    @exits.exit!(0)
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
    payload = parse(text) { { "died" => "", "signal" => status&.termsig, "code" => status&.exitstatus } }
    raise(Died.new(payload["died"], signal: payload["signal"], code: payload["code"])) if payload.key?("died")
    raise(rebuilt(payload)) if payload.key?("raised")
    payload.fetch("value")
  end

  def rebuilt(payload)
    kind = payload["raised"]
    message = payload["message"]
    error = kind == Timeout::Error.name ? Timeout::Error.new(message) : Raised.new(kind, message)
    error.tap { |rebuilt| rebuilt.set_backtrace(payload["frames"]) }
  end
end
