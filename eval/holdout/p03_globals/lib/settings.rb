module Settings
  def self.thresholds
    $health_thresholds ||= { warn: 50 + 20, crit: 100 - 10 }
  end
end
