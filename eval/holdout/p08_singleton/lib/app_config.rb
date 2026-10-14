class AppConfig
  attr_reader :page_size, :max_items

  def self.instance
    @instance ||= new
  end

  def initialize
    @page_size = 5 * 2
    @max_items = @page_size * 3
  end
end
