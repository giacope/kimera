# frozen_string_literal: true

require "json"
require "minitest"
require "zlib"
require_relative "../frameworks/class_hooks"
require_relative "../exits/test_exit"
require_relative "mirror_database"

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

Kimera::Execution::MirrorDatabase.new(request["slot"]).adopt

methods = {}
Minitest::Runnable.runnables.each do |runnable|
  next unless runnable.respond_to?(:runnable_methods)
  runnable.runnable_methods.each { |name| methods["#{runnable}##{name}"] = [runnable, name] }
end

messages = {}
failed =
  lambda do |id|
    klass, name = methods[id]
    next false unless klass
    File.write(pulse, ".", mode: "a") if pulse
    Kernel.srand((seed ^ Zlib.crc32(id)) % (2**31)) if seed
    result = Kimera::Frameworks::ClassHooks.new(klass).test(name)
    next false unless result && !result.passed? && !result.skipped?
    messages[id] = result.failures.first&.message.to_s[0, 2000]
    true
  end
killers = request["first_failure"] == false ? ids.select(&failed) : [ids.find(&failed)].compact

report = { failures: killers.size, failing: killers }
report[:message] = messages[killers.first] if killers.any?
File.write(ledger, JSON.generate(report))

exit(killers.empty? ? 0 : 1)
