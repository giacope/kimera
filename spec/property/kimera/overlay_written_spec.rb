# frozen_string_literal: true

require_relative "../property_helper"
require_relative "../../support/tree_shape"
require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# Every mutant kimera writes is the mutant: for each point and operator over
# kimera's own sources, the example apps and a fixed set of shapes the field
# corpus holds, the bake parses, differs from the original, and reads back as
# the mutated tree. Both sides are read the way kimera reads every file
# (numbered parameters named), written once by Scribe (which spells a sign, a
# heredoc or a call one way) and compared as TreeShape, a lone expression in
# parentheses being that expression. A factory-built constant is reopened on
# both sides alike. Every bake, and the warm overlay with every mutant off,
# keeps the file's line layout: as many lines, each definition on its line,
# and every line after the mutation (the point, and the bodies of the heredocs
# it holds) as it was, so no node after the mutation point moves: not
# `__LINE__`, a backtrace line, nor the `__LINE__ + 1` a `class_eval` heredoc
# hands down. A bake kimera refuses names an unbound local, or drops the
# newline a heredoc's text ends with: the mutants it cannot write.
# A seeded sample of files keeps it fast; `PBT_SCALE` widens it and
# `PBT_SEED` picks another.
RSpec.describe(Kimera::Overlay) do
  shapes = {
    "heredoc statements" => <<~'RUBY',
      def notice(io, name)
        io.puts <<~MSG
          careful, #{name}
          twice
        MSG
        log :warn, <<~TEXT
          gone
        TEXT
        where
      end

      def where = __LINE__
    RUBY
    "keyword hashes and permit lists" => <<~RUBY,
      class Budgets
        def label(scope)
          translate(:forbidden,
            scope: scope,
            default: "no")
        end

        def budget_params
          params.require(:budget).permit(
            :value,
            :budget_type,
            :currency
          )
        end

        def options = { a: 1,
                        b: [2,
                            3] }
      end
    RUBY
    "multi-line conditions and rescues" => <<~RUBY,
      module Gate
        def self.open?(a, b, c)
          a.positive? &&
            b.positive? && c.positive?
        end

        def self.parse(text)
          value = Integer(text)
          value > 0 ? value : -value
        rescue ArgumentError
          -1
        end

        CHECK = lambda do |x|
          begin
            x.call
          rescue ArgumentError
            x.size > 1
          end
        end
      end
    RUBY
    "heredocs the bake writes in place (R6B3-M4)" => <<~'RUBY',
      module Gen
        def self.reader(name, fallback)
          code = <<~CODE
            def #{name}
              @#{name} || #{
                fallback.inspect
              }
            end
          CODE
          [code, __LINE__]
        end

        def self.build(mod, column, cache)
          mod.class_eval <<~CODE, __FILE__, __LINE__ + 1
            def ancestors?
              read(:#{column}) != nil
            end
            #{if cache
              <<~INNER
                def cached
                  :#{cache}
                end
              INNER
            else
              <<-INNER
                def cached = nil
              INNER
            end}
            def depth
              #{column}.size
            end
          CODE
          mod.class_eval <<~'CODE', __FILE__, __LINE__ + 1
            def plain = "raw \#{text}"
          CODE
          [mod, __LINE__]
        end
      end
    RUBY
    "multi-line strings the bake writes in place" => <<~'RUBY',
      module Sql
        def self.count(tbl, pk, column)
          execute %{
            UPDATE #{tbl} AS dest
            SET dest.#{column} = (
              SELECT COUNT(*) FROM #{tbl} WHERE #{pk} = 1
            )
          }
          raise <<~EOS if pk.nil?
            Create the #{column} index:

              add_index :visits, [:token]
          EOS
          warn <<-EOS
            DELETE #{tbl}
            WHERE #{pk} = 1
          EOS
          [tbl, __LINE__]
        end
      end
    RUBY
    "bare lists, labels and `it` blocks" => <<~'RUBY'
      class Pair
        def initialize(left, right, list)
          @left, @right = left, right
          @all = *list, 1
          @named = { "#{left}_attributes": right, "plain": left }
        end

        def big(list) = list.select { it > 10 }.map { it.to_s }

        def halves(list) = list.map { _1 * 2 }.reject { |x| x.zero? }

        def keys = @all.map { it.key }.join("/")
      end
    RUBY
  }

  shapes.each do |shape, source|
    it "writes every mutant of its #{shape} as the mutated tree, on the file's lines" do
      expect(unlike("#{shape} fixture", source)).to(be_empty)
    end
  end

  seed = Integer(ENV.fetch("PBT_SEED", "20261023"))
  root = File.expand_path("../../..", __dir__)
  files = Dir[File.join(root, "{lib,examples}/**/*.rb")].reject { |path| path.include?("/vendor/") }.sort

  def read(text) = Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(text)).normalize

  def shape(text) = TreeShape.of(bare(read(Kimera::Scribe.new(read(text)).source)))

  def bare(node)
    return node.map { |item| bare(item) } if node.is_a?(Array)
    return node unless node.is_a?(Prism::Node)
    lone = lone(node)
    lone ? bare(lone) : node.copy(**children(node).transform_values { |value| bare(value) })
  end

  def lone(node)
    body = node.body if node.type == :parentheses_node
    body.body.first if body&.type == :statements_node && body.body.one?
  end

  def children(node) = node.deconstruct_keys(nil).select { |_, value| value.is_a?(Prism::Node) || value.is_a?(Array) }

  def expected(map, mutant, point)
    tree = Kimera::Guardrail.new(map, []).changes(point, mutant.directive).last.last
    written = Kimera::SourceMap.new(Kimera::Scribe.new(tree).source)
    shape(written.splice(Kimera::SpliceReopening.new(written).edits))
  end

  def unlike(path, source)
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["all"])).source(source, file: "x.rb")
    overlay = described_class.new(catalog)
    woven = laid(overlay.synthesize("x.rb", source).source, source)
    baked =
      catalog.each.filter_map do |mutant, point|
        problem = baked(overlay, source, mutant, point)
        "#{path}:#{point.location.start_line} #{mutant.label}: #{problem}" if problem
      end
    woven ? ["#{path}: the warm overlay #{woven}", *baked] : baked
  end

  def baked(overlay, source, mutant, point)
    written(overlay.bake("x.rb", source, mutant.id), source, mutant, point)
  rescue Kimera::Overlay::Unbakeable => error
    "unbakeable: #{error.message}" unless error.message.include?("Kimera::Scribe::Unbound") || ended?(source, point)
  end

  # A heredoc's text ends with a newline, so the mutant that drops the newline
  # of its last line has no heredoc to be written as, and kimera refuses it.
  def ended?(source, point)
    finish = point.location.finish
    found = []
    Kimera::Rewrite::AstWalk.new(Prism.parse(source).value).visit { |node| found << node if node.respond_to?(:heredoc?) && node.heredoc? }
    found.any? { |heredoc| heredoc.closing_loc.start_offset == finish }
  end

  def written(baked, source, mutant, point)
    return "does not parse" unless Prism.parse(baked).success?
    return "reads as the original" if baked == source
    map = Kimera::SourceMap.new(source)
    misread = -> { "misread" unless shape(baked) == expected(map, mutant, point) }
    laid(baked, source) || following(baked, map, point) || misread.call
  end

  # The first line after the mutation that the bake changes, if one is: the
  # mutation owns the point's lines and the bodies of the heredocs it holds;
  # the original is compared with a factory-built constant reopened, as the
  # bake writes it.
  def following(baked, map, point)
    original = map.splice(Kimera::SpliceReopening.new(map).edits).lines
    last = [point.location.end_line, *held(map.ast, point.location)].max
    moved = (last...original.size).find { |index| original[index] != baked.lines[index] }
    "changes line #{moved + 1}, after the mutation" if moved
  end

  def held(node, location)
    opening = node.location.start_offset
    own = node.respond_to?(:heredoc?) && node.heredoc? && opening.between?(location.start_offset, location.finish - 1)
    [*(node.closing_loc.start_line if own), *node.compact_child_nodes.flat_map { |child| held(child, location) }]
  end

  # How a written file moves the original's lines, if it does: a different
  # line count, or a definition outside the rewritten ones on another line.
  def laid(written, source)
    lines = [written, source].map { |text| text.lines.size }
    lines.uniq.one? ? moved(written, source) : "breaks #{lines.first} lines for #{lines.last}"
  end

  def moved(written, source)
    gone = definitions(Prism.parse(source).value) - definitions(Prism.parse(written).value)
    "moves #{gone.map { |name, line| "#{name} (line #{line})" }.join(", ")}" unless gone.empty?
  end

  def definitions(node)
    return [[node.name, node.location.start_line]] if node.type == :def_node
    node.compact_child_nodes.flat_map { |child| definitions(child) }
  end

  files.sample((6 * PropertyRuns::SCALE).ceil, random: Random.new(seed)).each do |path|
    it "writes every mutant of #{path.delete_prefix("#{root}/")} as the mutated tree" do
      expect(unlike(path, File.read(path, encoding: Encoding::UTF_8))).to(be_empty)
    end
  end
end
