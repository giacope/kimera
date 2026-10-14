# frozen_string_literal: true

require_relative "catalog/item"

# In-memory product catalog loaded from a pipe-separated text export:
#   SKU | Name | price | tag,tag | stock
class Catalog
  class ParseError < StandardError; end

  SKU_FORMAT = /\A[A-Z]{3}-\d{3}\z/

  def self.load(text)
    catalog = new
    text.each_line.with_index(1) do |line, number|
      next if line.strip.empty? || line.start_with?("#")

      catalog.add(parse_row(line, number))
    end
    catalog
  end

  def self.parse_row(line, number)
    sku, name, price, tags, stock = line.split("|").map(&:strip)
    raise ParseError, "line #{number}: bad sku #{sku.inspect}" unless SKU_FORMAT.match?(sku.to_s)
    raise ParseError, "line #{number}: missing name" if name.nil? || name.empty?

    Item.new(
      sku: sku,
      name: name,
      price_cents: parse_price(price, number),
      tags: tags.to_s.split(",").map { |t| t.strip.downcase }.reject(&:empty?).uniq,
      stock: stock.nil? || stock.empty? ? nil : Integer(stock)
    )
  end

  def self.parse_price(text, number)
    euros, cents = text.to_s.sub(/\AEUR/i, "").delete(" ").split(/[.,]/, 2)
    raise ParseError, "line #{number}: bad price #{text.inspect}" unless euros&.match?(/\A\d+\z/)

    cents = (cents || "0").ljust(2, "0")
    raise ParseError, "line #{number}: too many decimals in #{text.inspect}" if cents.length > 2

    (euros.to_i * 100) + cents.to_i
  end

  def initialize
    @items = {}
  end

  def add(item)
    raise ArgumentError, "duplicate sku #{item.sku}" if @items.key?(item.sku)

    @items[item.sku] = item
  end

  def size = @items.size
  def [](sku) = @items.fetch(sku)

  def tagged(tag)
    @items.values.select { |i| i.tags.include?(tag) }.map(&:sku).sort
  end

  def in_price_range(low_cents, high_cents)
    @items.values.select { |i| i.price_cents.between?(low_cents, high_cents) }.sort_by(&:price_cents).map(&:sku)
  end

  def restock(sku, quantity)
    raise ArgumentError, "quantity must be positive" unless quantity.positive?

    self[sku].stock += quantity
  end
end
