# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/rewrite/directive"

# R4-KR3: Prism rejects `next`, `break` and `redo` outside a block, so a
# report re-rendering a guard clause's point alone showed no mutated code.
RSpec.describe(Kimera::Rewrite::Directive) do
  let(:code) do
    <<~RUBY
      class Walk
        def odd(xs)
          xs.each do |x|
            next if x.even?
            break unless x < 9
            redo if x == 3
          end
        end
      end
    RUBY
  end

  def rendered
    Kimera::RegistryScan.new.source(code, file: "walk.rb").each.map do |mutant, point|
      [point.original_source, mutant.label, described_class.new(mutant.directive).render(point.original_source)]
    end
  end

  it "renders the mutants of a guard clause that leaves a block", :aggregate_failures do
    expect(rendered).to(
      include(
        ["next if x.even?", "condition => false", "next if false"],
        ["break unless x < 9", "condition => true", "break unless true"],
        ["redo if x == 3", "condition => true", "redo if true"],
        ["x < 9", "< => <=", "x <= 9"]
      )
    )
    expect(rendered.map(&:last)).to(all(be_a(String)))
  end

  it "renders a whole snippet that does not parse as nothing" do
    expect(described_class.new({ "type" => "comparison", "to" => "<=" }).render("x < 9\nend")).to(be_nil)
  end
end
