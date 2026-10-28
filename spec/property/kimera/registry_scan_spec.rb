# frozen_string_literal: true

require_relative "../property_helper"
require "kimera/registry/builder"

# The registry scan reads any Ruby it is given without raising (R6B6-M1: a
# method that opened with `if x` / `else ...` / `end` stopped every run whose
# scope held it). Scanned with every operator: shapes the field corpus held,
# kimera's own fixtures, and a seeded sample of the installed gems' files;
# each scan must end, report no file as one it could not scan, and anchor
# every point at its source. A file the scan trips on anyway is reported and
# skipped (spec/kimera/registry_scan_deferred_spec.rb). `PBT_SCALE` widens
# the sample and `PBT_SEED` picks another.
RSpec.describe(Kimera::RegistryScan) do
  shapes = {
    "an if whose only branch is its else (acts-as-taggable-on)" => <<~RUBY,
      class Tenant
        def column(ready)
          if ready
          else
            return :fresh
          end
          :kept
        end

        def tenant(taggable)
          if taggable
          else
            @tenant = :column
          end
          @tenant
        end
      end
    RUBY
    "an if whose first branch is empty before an elsif (net-http, irb)" => <<~RUBY,
      class Reader
        def read(body)
          if body
          elsif @socket
            return @socket.read
          else
            return
          end
          @read = true
        end

        def colored(token)
          unless token
          else
            return @cache[token] if @cache.key?(token)
          end
          @cache[token] = token.to_s
        end
      end
    RUBY
    "empty bodies, branches and clauses" => <<~RUBY
      class Empty
        def a; end
        def b = nil
        def c
          if x
          end
          unless y
          end
          begin
          rescue
          ensure
          end
        end
        def d
        rescue
        else
        ensure
        end
      end
    RUBY
  }

  seed = Integer(ENV.fetch("PBT_SEED", "20261028"))
  count = (12 * PropertyRuns::SCALE).ceil
  root = File.expand_path("../../..", __dir__)
  fixtures = Dir[File.join(root, "{examples,eval,spec/property/corpus}/**/*.rb")]
  gems = Gem.loaded_specs.values.flat_map { |spec| Dir[File.join(spec.full_gem_path, "{lib,app}/**/*.rb")] }
  gems = gems.uniq.select { |path| File.size(path) < 60_000 }.sort
  sampled = fixtures.sample(count, random: Random.new(seed)) + gems.sample(count * 3, random: Random.new(seed))

  def unscanned(path, source)
    registry = described_class.new(operators: Kimera::Operators.build(keys: ["all"])).source(source, file: path)
    tripped = registry.unmutated.map(&:reason).select { |reason| reason.start_with?(Kimera::Unmutated::UNSCANNED) }
    tripped + registry.points.reject { |point| anchored?(point, source) }.map { "point #{it.point_id} moved" }
  end

  def anchored?(point, source)
    source.byteslice(point.location.start_offset, point.location.span) == point.original_source
  end

  shapes.each do |shape, source|
    it "scans #{shape} whole" do
      expect(unscanned("x.rb", source)).to(be_empty)
    end
  end

  sampled.each do |path|
    it "scans #{path.delete_prefix("#{root}/").sub(%r{\A.*/gems/}, "")} whole" do
      expect(unscanned(File.basename(path), File.read(path, encoding: Encoding::UTF_8))).to(be_empty)
    end
  end
end
