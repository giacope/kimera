module Gate
  def self.open?(load)
    load > 5 && load <= 50
  end
end
