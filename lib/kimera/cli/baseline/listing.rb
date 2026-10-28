# frozen_string_literal: true

class Kimera::CLI::Baseline::Listing
  def initialize(io)
    @io = io
  end

  def show(heading, entries)
    return if entries.empty?
    @io.puts(*heading)
    entries.each { |entry| @io.puts(yield(entry)) }
  end
end
