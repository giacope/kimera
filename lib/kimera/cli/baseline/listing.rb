# frozen_string_literal: true

class Kimera::CLI::Baseline::Listing
  def initialize(heading, entries)
    @heading = heading
    @entries = entries
  end

  def lines(&) = @entries.empty? ? [] : [*@heading, *@entries.map { |entry| entry.remark(&) }]
end
