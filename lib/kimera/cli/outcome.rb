# frozen_string_literal: true

module Kimera
  class CLI
  end
end

module Kimera::CLI::Outcome
  class Said
    def initialize(*lines)
      @lines = lines
    end

    def print(io, _errors)
      io.puts(*@lines)
      self
    end

    def exit(process = Kernel) = process.exit(0)
  end

  class Written
    def initialize(text, status = 0)
      @text = text
      @status = status
    end

    def print(io, _errors)
      io.write(@text)
      self
    end

    def exit(process = Kernel) = process.exit(@status)
  end

  class Failed
    def initialize(status, *lines)
      @status = status
      @lines = lines
    end

    def print(_io, errors)
      errors.puts(*@lines)
      self
    end

    def exit(process = Kernel) = process.exit(@status)
  end

  class Ended
    def initialize(status)
      @status = status
    end

    def print(_io, _errors) = self

    def exit(process = Kernel) = process.exit(@status)
  end
end
