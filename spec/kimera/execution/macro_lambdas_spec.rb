# frozen_string_literal: true

require "fileutils"
require "kimera/execution/macro_lambdas"
require "kimera/registry/builder"
require "tmpdir"

# once-campfire: re-declaring `belongs_to :creator, default: -> { Current.user }`
# warm adds a second callback, and the original runs first, so the mutated
# lambda never runs and its mutants read as untested.
RSpec.describe(Kimera::Execution::MacroLambdas) do
  let(:source) do
    <<~RUBY
      class MacroLambdaBoost
        belongs_to :booster, default: -> { Current.user }
        scope :ordered, -> { order(:created_at) }
        LIMIT = -> { size > 10 }

        def score(a, b)
          check = -> { a > b }
          check.call
        end

        def rank(a, b) = run(-> { a < b })
      end
    RUBY
  end

  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "boost.rb").tap { |path| File.write(path, source) } }
  let(:registry) { Kimera::RegistryScan.new(root: dir).build([file]) }

  after { FileUtils.remove_entry(dir) }

  def point(text) = registry.points.find { |found| found.original_source == text }

  it "sends an uncovered lambda a class-body macro is handed to the isolated tier", :aggregate_failures do
    described_class.new(registry, dir).quarantine!({})
    expect(point("Current.user")).to(have_attributes(safe?: false, unsafe_reason: Kimera::MutationPoint::MACRO_REASON))
    expect(point("Current.user").reloadable?).to(be(false))
  end

  it "leaves a macro's lambda a test covers, by integer or string id", :aggregate_failures do
    booster = point("Current.user")
    ordered = point("order(:created_at)")
    described_class.new(registry, dir).quarantine!({ booster.ids.first => ["t1"], ordered.ids.first.to_s => ["t1"] })
    expect([booster.safe?, ordered.safe?]).to(eq([true, true]))
  end

  it "leaves lambdas no class-body macro is handed: a constant's, and those in a method", :aggregate_failures do
    described_class.new(registry, dir).quarantine!({})
    expect([point("size > 10"), point("a > b"), point("a < b")].map(&:safe?)).to(eq([true, true, true]))
  end

  it "leaves a point sent elsewhere already, for a reason or a revisit of its own", :aggregate_failures do
    point("Current.user").unsafe!(Kimera::MutationPoint::LOAD_REASON)
    point("order(:created_at)").revisit!(Kimera::MutationPoint::BOOT_REASON)
    described_class.new(registry, dir).quarantine!({})
    expect(point("Current.user").unsafe_reason).to(eq(Kimera::MutationPoint::LOAD_REASON))
    expect(point("order(:created_at)").safe?).to(be(true))
  end

  it "leaves the points of a file that is gone" do
    registry
    File.delete(file)
    described_class.new(registry, dir).quarantine!({})
    expect(point("Current.user").safe?).to(be(true))
  end
end
