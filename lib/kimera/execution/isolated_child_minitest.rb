# frozen_string_literal: true

require "json"
require "minitest"

Minitest.seed ||= 1
begin
  Minitest.class_variable_set(:@@installed_at_exit, :installed)
rescue NameError, ArgumentError
  class << Minitest
    def run(*) = true
  end
end

ledger, *rest = ARGV
split = rest.index("--") or abort("usage: <ledger> <test files...> -- <ids...>")
files = rest[0...split]
ids = rest[(split + 1)..]
ARGV.clear

files.each { |f| require File.expand_path(f) }

methods = {}
Minitest::Runnable.runnables.each do |runnable|
  next unless runnable.respond_to?(:runnable_methods)
  runnable.runnable_methods.each { |name| methods["#{runnable}##{name}"] = [runnable, name] }
end

killer =
  ids.find do |id|
    klass, name = methods[id]
    next false unless klass
    result = klass.new(name).run
    !result.passed? && !result.skipped?
  end

File.write(ledger, JSON.generate(failures: killer ? 1 : 0, failing: [killer].compact))

exit(killer ? 1 : 0)
