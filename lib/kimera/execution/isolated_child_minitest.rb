# frozen_string_literal: true

require "json"
require "minitest"
require "zlib"
require_relative "../support/class_hooks"
require_relative "../support/test_exit"

Minitest.seed ||= 1
begin
  Minitest.class_variable_set(:@@installed_at_exit, :installed)
rescue NameError, ArgumentError
  Minitest.singleton_class.prepend(Module.new { def run(*) = true })
end

ledger, request, pulse = ARGV
request = JSON.parse(File.read(request, encoding: Encoding::UTF_8))
seed = request["seed"]
Minitest.seed = seed if seed
files = request.fetch("files")
ids = request.fetch("tests")
ARGV.clear

begin
  files.each { |f| require File.expand_path(f) }
rescue StandardError, ScriptError => error
  cause = ["#{error.class}: #{error.message}", *Array(error.backtrace).first(5).map { |line| "  #{line}" }]
  File.write(ledger, JSON.generate(failures: 1, failing: [], load_error: cause.join("\n")))
  exit(1)
end

methods = {}
Minitest::Runnable.runnables.each do |runnable|
  next unless runnable.respond_to?(:runnable_methods)
  runnable.runnable_methods.each { |name| methods["#{runnable}##{name}"] = [runnable, name] }
end

failed =
  lambda do |id|
    klass, name = methods[id]
    next false unless klass
    File.write(pulse, ".", mode: "a") if pulse
    Kernel.srand((seed ^ Zlib.crc32(id)) % (2**31)) if seed
    result = Kimera::ClassHooks.new(klass).run { klass.new(name).extend(Kimera::TestExit::Test).run }
    result && !result.passed? && !result.skipped?
  end
killers = request["first_failure"] == false ? ids.select(&failed) : [ids.find(&failed)].compact

File.write(ledger, JSON.generate(failures: killers.size, failing: killers))

exit(killers.empty? ? 0 : 1)
