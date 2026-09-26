# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Reload; end

Kimera::Execution::Reload::Errand =
  Struct.new(:id, :tests, :reader, :writer) do
    tick = "tick\n"
    def parent!
      writer.close
    end

    def child!
      reader.close
      writer.sync = true
    end
    define_method(:tick) { writer.write(tick) }
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
  end
