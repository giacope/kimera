# frozen_string_literal: true

require "kimera/incremental/selection"
require "kimera/registry/builder"

RSpec.describe(Kimera::Incremental::Selection) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  describe ".changed" do
    it "selects mutants on the lines GitDiff reports as changed" do
      changed = { "calc.rb" => Set[2] } # the `x > y` line
      allow(Kimera::Incremental::GitDiff).to(
        receive(:new).with(
          since: "main",
          root: "."
        ).and_return(instance_double(Kimera::Incremental::GitDiff, lines: changed))
      )

      ids = described_class.changed(registry, since: "main")
      sources = ids.map { |id| registry.index[id].original_source }.uniq
      expect(sources).to(eq(["x > y"]))
    end

    it "passes a custom root through to GitDiff" do
      allow(Kimera::Incremental::GitDiff).to(
        receive(:new).with(
          since: "dev",
          root: "/proj"
        ).and_return(instance_double(Kimera::Incremental::GitDiff, lines: {}))
      )
      expect(described_class.changed(registry, since: "dev", root: "/proj")).to(eq([]))
    end
  end
end
