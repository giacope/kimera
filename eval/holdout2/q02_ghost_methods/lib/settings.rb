# frozen_string_literal: true

# Configuration bag with dynamic accessors. The first call to an accessor
# goes through method_missing, which defines a real method on the class so
# that every later call (in any instance) skips method_missing entirely.
class Settings
  TRUE_WORDS = %w[true yes on 1].freeze

  def self.defaults
    { "timeout" => 30, "retries" => 3, "verbose" => false, "label" => "app" }
  end

  def self.materialized
    @materialized ||= []
  end

  def initialize(overrides = {})
    @values = self.class.defaults.merge(overrides.transform_keys(&:to_s))
  end

  def keys
    @values.keys.sort
  end

  def respond_to_missing?(name, include_private = false)
    key, = parse(name)
    @values.key?(key) || super
  end

  def method_missing(name, *args)
    key, kind = parse(name)
    return super unless @values.key?(key)

    expected = kind == :writer ? 1 : 0
    raise ArgumentError, "#{name}: expected #{expected} arguments, got #{args.size}" if args.size != expected

    self.class.materialize(name, key, kind)
    public_send(name, *args)
  end

  def self.materialize(name, key, kind)
    return if method_defined?(name)

    case kind
    when :writer then define_method(name) { |value| @values[key] = coerce(key, value) }
    when :predicate then define_method(name) { truthy?(@values[key]) }
    when :toggle then define_method(name) { @values[key] = !truthy?(@values[key]) }
    else define_method(name) { @values[key] }
    end
    materialized << name
  end

  private

  def parse(name)
    str = name.to_s
    if str.end_with?("=") then [str.chomp("="), :writer]
    elsif str.end_with?("?") then [str.chomp("?"), :predicate]
    elsif str.start_with?("toggle_") then [str.delete_prefix("toggle_"), :toggle]
    else [str, :reader]
    end
  end

  def truthy?(value)
    !(value.nil? || value == false || value == 0 || value == "")
  end

  def coerce(key, value)
    case @values[key]
    when Integer then Integer(value)
    when true, false then TRUE_WORDS.include?(value.to_s.downcase)
    else value
    end
  end
end
