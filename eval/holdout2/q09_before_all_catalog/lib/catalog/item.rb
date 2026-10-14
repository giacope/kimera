# frozen_string_literal: true

class Catalog
  Item = Struct.new(:sku, :name, :price_cents, :tags, :stock, keyword_init: true) do
    def self.default_stock
      @default_stock ||= 0
    end

    def self.default_stock=(value)
      @default_stock = value
    end

    def initialize(**fields)
      super
      self.tags ||= []
      self.stock ||= self.class.default_stock
    end

    def in_stock?
      stock.positive?
    end

    def price
      format("%d.%02d", price_cents / 100, price_cents % 100)
    end
  end
end
