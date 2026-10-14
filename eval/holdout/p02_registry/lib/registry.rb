require_relative "rules"

module Registry
  def self.table
    @table ||= Rules.all
  end

  def self.score(n)
    table.values.sum { |rule| rule.call(n) } + n
  end
end
