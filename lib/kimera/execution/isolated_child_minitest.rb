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

split = ARGV.index("--") or abort("usage: <test files...> -- <ids...>")
files = ARGV[0...split]
ids = ARGV[(split + 1)..]

files.each { |f| load File.expand_path(f) }

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

if (ledger = ENV.fetch("KIMERA_ISOLATED_LEDGER", nil))
  File.write(ledger, JSON.generate(failures: killer ? 1 : 0, failing: [killer].compact))
end

exit(killer ? 1 : 0)
