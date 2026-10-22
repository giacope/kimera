# frozen_string_literal: true

# A plain-Ruby `validates` stands in for Rails. It accumulates state at load,
# so these mutants can't be judged in-process.
RSpec.describe("rails class-body operators (end-to-end)") do
  def files = {
    "app/signup.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Signup
        def self.validators = @validators ||= []
        def self.validates(field, **_opts) = validators << field
        validates :email, presence: true
        def valid?(data)
          self.class.validators.all? { |field| data[field] }
        end
      end
    RUBY
    "spec/signup_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/signup"

      RSpec.describe Signup do
        it { expect(Signup.new.valid?(email: "a@b.c")).to be(true) }
        it { expect(Signup.new.valid?({})).to be(false) }
      end
    RUBY
  }

  def operated(fixture, *flags) = test_outcome(cwd: fixture, arguments: ["--operators", "rails_validation", *flags])

  def isolated_hint = "only the isolated tier can judge (run with --isolated)"

  # The warm run alone evaluates nothing here, so its gate fails and names
  # --isolated rather than passing on 0 of 1.
  it "defers class-body mutants on the warm path and kills them isolated", :aggregate_failures do
    test_tree(files, "kimera-rails-ops") do |fixture|
      warm, isolated = [[], ["--isolated"]].map { |flags| operated(fixture, *flags) }
      expect([warm.counts.slice("isolated_only", "survived"), warm.status, warm.output]).to(
        match([{ "isolated_only" => 1, "survived" => 0 }, 2, a_string_including(isolated_hint)])
      )
      expect([isolated.counts.slice("killed", "isolated_only", "error"), isolated.status]).to(
        eq([{ "killed" => 1, "isolated_only" => 0, "error" => 0 }, 0]), isolated.output
      )
    end
  end
end
