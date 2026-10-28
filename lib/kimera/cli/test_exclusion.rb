# frozen_string_literal: true

class Kimera::CLI::TestExclusion
  RSPEC = <<~RUBY
    require "rspec/core"
    names = %s
    RSpec.configure do |config|
      config.filter_run_excluding(
        full_description: lambda do |text, meta|
          id = "\#{meta[:rerun_file_path]}[\#{meta[:scoped_id]}]"
          names.any? { |name| name.match?(text.to_s) || name.match?(id) }
        end
      )
    end
  RUBY
  RUNNER = "exit(RSpec::Core::Runner.run(ARGV))"
  MINITEST = "ARGV.push(\"--exclude\", %s)"

  def initialize(framework, names)
    @framework = framework
    @names = names
  end

  def none? = @names.empty?

  def before = none? || minitest? ? [] : ["-e", format(RSPEC, patterns.inspect)]

  def after = none? || !minitest? ? [] : ["-e", format(MINITEST, Regexp.union(patterns).inspect.inspect)]

  def rspec(flags, files)
    none? ? ["bundle", "exec", "rspec", *flags, *files] : ruby([], ["-e", RUNNER, "--", *flags], files)
  end

  def ruby(head, script, files) = ["bundle", "exec", "ruby", *head, *before, *script, *after, *files]

  private

  def patterns = @names.map { |name| Regexp.new(name) }

  def minitest? = @framework == "minitest"
end
