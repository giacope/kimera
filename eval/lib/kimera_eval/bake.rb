# frozen_string_literal: true

require "json"
require "kimera"
require "kimera/cli"
require "kimera/cli/run"

module KimeraEval
end

class KimeraEval::Bake
  def initialize(registry, overlay: Kimera::Overlay.new(registry))
    @registry = registry
    @overlay = overlay
  end

  def call(id)
    point = @registry.index[id]
    return { "error" => "unknown mutant" } unless point
    file = point.to_h.fetch("file")
    { "file" => file, "source" => @overlay.bake(file, File.read(file, encoding: Encoding::UTF_8), id) }
  rescue Kimera::Overlay::Unbakeable => error
    { "error" => "#{error.class}: #{error.message}" }
  end
end

options = Kimera::CLI::Run::Arguments.new.parse(ARGV.dup)
bake = KimeraEval::Bake.new(Kimera::CLI::Run::Sources.new(errors: $stderr).load(options))
$stdout.write(JSON.generate(JSON.parse($stdin.read).to_h { |id| [id, bake.call(id)] }))
