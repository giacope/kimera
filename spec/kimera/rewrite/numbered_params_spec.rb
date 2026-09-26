# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

RSpec.describe(Kimera::Rewrite::NumberedParams) do
  it "renames only lvar references, never a literal :_1 symbol" do
    node = described_class.normalize(Unparser.parse("x { [:_1, _1] }"))
    expect(Unparser.unparse(node)).to(include("[:_1, __kimera_1]"))
  end

  def normalize(source)
    Unparser.unparse(described_class.normalize(Unparser.parse(source)))
  end

  it "renames numbered params so interpolation survives unparsing", :aggregate_failures do
    # Single-quoted: the #{} is source text for the parser.
    out = normalize('x.each { puts "a #{_1} b #{_2}" }')

    expect(out).to(include("|__kimera_1, __kimera_2|"))
    expect(out).to(include('puts("a #{__kimera_1} b #{__kimera_2}")'))

    expect { Unparser.parse(out) }.not_to(raise_error)
  end

  it "renames it-blocks", :aggregate_failures do
    out = normalize('x.each { puts "a #{it}" }')

    expect(out).to(include("|__kimera_it|"))
    expect(out).to(include('puts("a #{__kimera_it}")'))
  end

  it "keeps single-parameter non-destructuring semantics (procarg0)", :aggregate_failures do
    expect(eval(normalize("[[1, 2]].map { _1 }"))).to(eq([[1, 2]]))

    expect(eval(normalize("[[1, 2]].map { it }"))).to(eq([[1, 2]]))
  end

  it "scopes renames to the owning block, including nested it-blocks", :aggregate_failures do
    out = normalize("a.map { it + b.map { it * 2 }.sum }")
    expect { Unparser.parse(out) }.not_to(raise_error)
    expect(out.scan("__kimera_it").size).to(eq(4))
  end

  it "leaves ordinary blocks alone" do
    expect(normalize("x.sort_by { |a| a.size }")).to(eq("x.sort_by { |a|\n  a.size\n}"))
  end

  it "makes a file using _1 in interpolation synthesizable end to end", :aggregate_failures do
    source = <<~RUBY
      class Printer
        def show(list)
          list.map { "· \#{_1}" }
        end
      end
    RUBY
    registry = Kimera::RegistryScan.new.source(source, file: "x.rb")
    result = Kimera::Overlay.new(registry).synthesize("x.rb", source)
    expect(result.mutant_ids).not_to(be_empty)
    expect { Unparser.parse(result.source) }.not_to(raise_error)
  end
end
