require_relative "settings"

module Health
  def self.level(value)
    t = Settings.thresholds
    if value >= t[:crit]
      :critical
    elsif value >= t[:warn]
      :warning
    else
      :ok
    end
  end

  def self.alert?(values)
    values.count { |v| level(v) != :ok } >= 2
  end
end
