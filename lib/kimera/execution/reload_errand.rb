# frozen_string_literal: true

require "json"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Reload; end

Kimera::Execution::Reload::Errand =
  Struct.new(:id, :tests, :reader, :writer) do
    tick = "tick\n"
    private(*members)
    def parent!
      writer.close
    end

    def child!
      reader.close
      writer.sync = true
    end
    define_method(:tick) do |test|
      ran << test
      writer.write(tick)
    end
    def ran = @_ran ||= []

    def reach(test) = reached << test

    def covered? = !reached.empty?

    def failures(&) = tests.lazy.map(&).reject(&:passed?).first(1)

    def report(**fields) = JSON.generate(id: id, **fields, cover: reached)

    def emit(payload)
      writer.puts(payload)
      writer.close
    end

    def await(deadline)
      heard(deadline).tap { |line| yield if line == :timeout }
    ensure
      reader.close
    end
    define_method(:heard) do |deadline|
      while reader.wait_readable(deadline)
        line = reader.gets
        return line unless line == tick
      end
      :timeout
    end
    private
    def reached = @_reached ||= []
  end
