# frozen_string_literal: true

# Runs under the kimera checkout being evaluated, in the project directory:
# builds the registry `kimera run ARGV` would build and prints, for each
# mutant id read from stdin, the whole source of its file with that one
# mutant applied (what --isolated would run), or why it can't be baked.
require "json"
require "kimera"
require "kimera/cli"
require "kimera/cli/run"

options = Kimera::CLI::Run::Arguments.new.parse(ARGV.dup)
registry = Kimera::CLI::Run::Sources.new(errors: $stderr).load(options)
overlay = Kimera::Overlay.new(registry)
baked = JSON.parse($stdin.read).to_h do |id|
  point = registry.index[id]
  next [id, { "error" => "unknown mutant" }] unless point
  source = File.read(point.file, encoding: Encoding::UTF_8)
  [id, { "file" => point.file, "source" => overlay.bake(point.file, source, id) }]
rescue StandardError => e
  [id, { "error" => "#{e.class}: #{e.message}" }]
end
$stdout.write(JSON.generate(baked))
