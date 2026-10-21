# frozen_string_literal: true

# The visibility operator end to end: the warm run flips a method private on
# activation, and its verdicts match the isolated tier's, which bakes
# `private(:name)` into a fresh copy of the project.
RSpec.describe("kimera run --operators visibility (end-to-end)") do
  def project(root)
    FileUtils.mkdir_p(File.join(root, "app"))
    FileUtils.mkdir_p(File.join(root, "spec"))
    File.write(File.join(root, "app", "ledger.rb"), <<~RUBY)
      # frozen_string_literal: true
      class Ledger
        def total = entries.sum
        def entries = [1, 2]
        def audit = :ok
        def ghost = :real

        def method_missing(name, *args) = name == :ghost ? :ghosted : super
        def respond_to_missing?(name, include_private = false) = name == :ghost || super
      end
    RUBY
    File.write(File.join(root, "spec", "ledger_spec.rb"), <<~RUBY)
      # frozen_string_literal: true
      require_relative "../app/ledger"

      RSpec.describe Ledger do
        it { expect(Ledger.new.total).to eq(3) }
        it { expect(Ledger.new.__send__(:audit)).to eq(:ok) }
        it { expect(Ledger.new.ghost).to eq(:real) }
      end
    RUBY
  end

  def statuses(report) = report["results"].to_h { |result| [result["method"], result["status"]] }

  it "kills a method tests call from outside, spares one called only inside or through send", :aggregate_failures do
    Dir.mktmpdir("kimera-visibility") do |root|
      project(root)
      expected = { "total" => "killed", "entries" => "survived", "audit" => "survived", "ghost" => "killed" }
      [[], ["--isolated"]].each do |mode|
        test_run(cwd: root, arguments: ["--operators", "visibility", *mode]) do |output, report, _status|
          expect(report).not_to(be_nil, "no report; output:\n#{output}")
          expect(statuses(report)).to(eq(expected), "#{mode.inspect}:\n#{output}")
        end
      end
    end
  end
end
