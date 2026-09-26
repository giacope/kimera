# frozen_string_literal: true

# A plain-Ruby `validates` stands in for Rails. It accumulates state at load,
# so these mutants can't be judged in-process.
RSpec.describe("rails class-body operators (end-to-end)") do
  def write(fixture)
    FileUtils.mkdir_p(File.join(fixture, "app"))
    FileUtils.mkdir_p(File.join(fixture, "spec"))
    File.write(File.join(fixture, "app", "signup.rb"), <<~RUBY)
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
    File.write(File.join(fixture, "spec", "signup_spec.rb"), <<~RUBY)
      # frozen_string_literal: true
      require_relative "../app/signup"

      RSpec.describe Signup do
        it { expect(Signup.new.valid?(email: "a@b.c")).to be(true) }
        it { expect(Signup.new.valid?({})).to be(false) }
      end
    RUBY
  end

  it "defers class-body mutants on the warm path and kills them isolated", :aggregate_failures do
    Dir.mktmpdir("kimera-rails-ops") do |fixture|
      write(fixture)
      ops = ["--operators", "rails_validation"]

      test_run(cwd: fixture, args: ops) do |output, report, status|
        expect(report).not_to(be_nil, "no report; output:\n#{output}")
        expect(report["counts"]["isolated_only"]).to(eq(1))
        expect(report["counts"]["survived"]).to(eq(0))
        expect(status).to(eq(0))
      end

      test_run(cwd: fixture, args: [*ops, "--isolated"]) do |output, report, _status|
        expect(report).not_to(be_nil, "no report; output:\n#{output}")
        expect(report["counts"]["killed"]).to(eq(1))
        expect(report["counts"]["isolated_only"]).to(eq(0))
        expect(report["counts"]["error"]).to(eq(0))
      end
    end
  end
end
