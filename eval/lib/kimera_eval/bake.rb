# frozen_string_literal: true

require "json"
require "kimera"
require "kimera/cli"
require "kimera/cli/run"

module KimeraEval
end

# One mutant's file, baked. This script runs under the kimera checkout being
# evaluated, in the project directory: it builds the registry `kimera run ARGV`
# would build and prints, for each mutant id read from stdin, the whole source
# of its file with that one mutant applied (what --isolated would run), or why
# it can't be baked.
class KimeraEval::Bake
  def initialize(registry)
    @registry = registry
  end

  def call(id)
    point = @registry.index[id]
    return { "error" => "unknown mutant" } unless point
    { "file" => point.file, "source" => baked(point, id) }
  rescue StandardError => error
    { "error" => "#{error.class}: #{error.message}" }
  end

  private

  def baked(point, id) = overlay.bake(point.file, File.read(point.file, encoding: Encoding::UTF_8), id)

  def overlay = @_overlay ||= Kimera::Overlay.new(@registry)
end

options = Kimera::CLI::Run::Arguments.new.parse(ARGV.dup)
bake = KimeraEval::Bake.new(Kimera::CLI::Run::Sources.new(errors: $stderr).load(options))
$stdout.write(JSON.generate(JSON.parse($stdin.read).to_h { |id| [id, bake.call(id)] }))
