# frozen_string_literal: true

# R3K5: code .rspec's --require loaded ran before kimera's load trace began.
# R3K2: a lambda a class body calls ran while loading, not as a method.
# K3-7: an in-scope file the suite never loads was evaluated anyway.
RSpec.describe("kimera run on code that runs while the suite loads (end-to-end)", :aggregate_failures) do
  def files = {
    ".rspec" => "--require spec_helper\n",
    "spec/spec_helper.rb" =>
      "require_relative \"../app/flags\"\nrequire_relative \"../app/limits\"\nSETTINGS = { greet: \"hello\" }\n",
    "app/flags.rb" => <<~RUBY,
      class Flags
        def self.flag(key)
          define_method(:"\#{key}?") { (@set ||= {})[key] == true }
          define_method(:"\#{key}!") { (@set ||= {})[key] = true }
        end
        private_class_method :flag

        flag :strict
      end
    RUBY
    "app/limits.rb" => <<~RUBY,
      class Limits
        env_int = lambda do |val|
          val if val >= 0
        end
        MAX = env_int.call(4096)
      end
    RUBY
    "app/setup.rb" => "SETTINGS[:greet] = -> { 1 > 0 ? \"hi from a file nothing loads\" : \"\" }\n",
    "spec/flags_spec.rb" => <<~RUBY
      RSpec.describe(Flags) do
        it("is unset") { expect(Flags.new.strict?).to be(false) }
        it("is set") { expect(Flags.new.tap(&:strict!).strict?).to be(true) }
        it("caps") { expect(Limits::MAX).to eq(4096) }
        it("greets") { expect(SETTINGS[:greet]).to eq("hello") }
      end
    RUBY
  }

  def loaded(arguments = []) = test_tree(files, "kimera-load") { |root| test_outcome(cwd: root, arguments: arguments) }

  it "judges load-time code in the isolated tier and never evaluates a file nothing loads", :aggregate_failures do
    run = loaded
    expect(%w[app/flags.rb app/limits.rb app/setup.rb].map { |file| run.statuses(file) } << run.status)
      .to(eq([["isolated_only"], ["isolated_only"], ["no_coverage"], 2]), run.output)
    expect(run.rows("app/setup.rb").map { |r| r["detail"] }.uniq).to(eq([Kimera::MutationPoint::NEVER_LOADED]))
  end

  it "kills the load-time mutants a test can see when judged in mirrors" do
    run = loaded(["--isolated", "--exclude", "app/setup.rb"])
    expect([run.rows("app/flags.rb").map { |r| r["status"] }, run.counts["no_coverage"]])
      .to(match([include("killed"), 0]), run.output)
  end
end
