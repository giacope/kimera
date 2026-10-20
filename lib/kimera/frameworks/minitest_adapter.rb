# frozen_string_literal: true

require_relative "adapter"
require_relative "load_path"
require_relative "class_hooks"
require_relative "../support/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::MinitestAdapter < Kimera::Frameworks::Adapter
  INSTALLED = true
  CONSTANT = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/
  PLAIN = %r{\A[\w./@:+-]+\z}

  class << self
    def build
      require("minitest")
      new.disarmed
    end
  end

  def disarmed
    Minitest.seed ||= 1
    disarm
    self
  end

  def source(files)
    Kimera::Seed.new.value&.then { |seed| Minitest.seed = seed }
    paths(files)
    each_test_file(files) { |file| require(file) }
    indexed
    self
  end

  def test_ids
    indexed.keys
  end

  def run(ids)
    outcome(ids.filter_map { |id| record(id) })
  end

  def locate(id) = { "location" => definition(*indexed.fetch(id)).join(":") }

  def test_file(id) = indexed[id]&.then { |klass, name| declared(klass.name) || definition(klass, name).first }

  def reproduce(ids)
    "bundle exec ruby #{includes(ids)} -rminitest/autorun -e #{quote(loads(ids))} " \
      "-- -n #{quote("/^(?:#{ids.map { |id| Regexp.escape(id) }.join("|")})$/")} --seed #{Minitest.seed}"
  end

  private

  def disarm
    Minitest.class_variable_set(:@@installed_at_exit, INSTALLED)
  rescue NameError, ArgumentError
    Minitest.define_singleton_method(:run) { |*| true }
  end

  def includes(ids)
    flags = Kimera::Frameworks::LoadPath.new(ids.filter_map { |id| origin(id) }).flags
    flags.each_slice(2).map { |flag, dir| "#{flag}#{shell(dir)}" }.join(" ")
  end

  def shell(word) = word.match?(PLAIN) ? word : quote(word)

  def loads(ids)
    ids.filter_map { |id| origin(id) }.uniq.map { |file| "require File.expand_path(#{file.dump})" }.join("; ")
  end

  def origin(id) = indexed[id]&.then { |found| definition(*found).first }

  def declared(named) = named&.match?(CONSTANT) && Object.const_source_location(named)&.first

  def definition(klass, name)
    path, line = klass.instance_method(name).source_location
    [path.delete_prefix("#{Dir.pwd}#{File::SEPARATOR}"), line]
  end

  def quote(text) = "'#{text.gsub("'") { "'\\''" }}'"

  def record(id)
    klass, name = indexed[id]
    return unless klass
    reseed(id)
    result = Kimera::Frameworks::ClassHooks.new(klass).test(name)
    [id, message(result)] if result && killing?(result)
  end

  def paths(files) = Kimera::Frameworks::LoadPath.new(files).install

  def indexed
    @_indexed ||= Minitest::Runnable.runnables.flat_map do |runnable|
      runnable.runnable_methods.map { |name| ["#{runnable}##{name}", [runnable, name]] }
    end.to_h
  end

  def killing?(result) = !result.passed? && !result.skipped?

  def message(result)
    assertion = result.failures.first
    assertion && [headline(assertion), *trace(assertion)].join("\n    ")
  end

  def trace(assertion) = frames(Minitest.filter_backtrace(Array(assertion.backtrace)))

  def headline(assertion)
    kind = assertion.class.name.split("::").last
    return "#{kind}: #{assertion.message}" unless assertion.is_a?(Minitest::UnexpectedError)
    error = assertion.error
    "#{kind}: #{error.class}: #{error.message}"
  end
end

Kimera::Frameworks::ADAPTERS.register(:minitest, Kimera::Frameworks::MinitestAdapter)
