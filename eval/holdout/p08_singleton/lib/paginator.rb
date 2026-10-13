require_relative "app_config"

class Paginator
  def initialize(total)
    @total = [total, AppConfig.instance.max_items].min
  end

  def per
    AppConfig.instance.page_size
  end

  def pages
    (@total + per - 1) / per
  end

  def range(page)
    raise ArgumentError, "bad page" if page < 1 || page > pages

    first = (page - 1) * per
    first...[first + per, @total].min
  end
end
