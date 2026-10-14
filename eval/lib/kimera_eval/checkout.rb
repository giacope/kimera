# frozen_string_literal: true

module KimeraEval
  class SetupError < StandardError; end

  # The kimera checkout under evaluation, run from its own bundle.
  class Checkout
    LIMIT = 900

    def initialize(path)
      @given = path
    end

    def path = @_path ||= File.expand_path(@given)

    def prepare!
      raise(SetupError, "not a kimera checkout: #{path}") unless File.file?(File.join(path, "exe", "kimera"))
      return if shell.run("bundle", "check").ok?
      result = shell.run("bundle", "install")
      raise(SetupError, "bundle install failed in #{path}:\n#{result.output}") unless result.ok?
    end

    def gemfile = File.join(path, "Gemfile")

    def revision = shell.run("git", "-C", path, "rev-parse", "--short", "HEAD").stdout.strip

    def cli(*, chdir:, env: {}, timeout: LIMIT)
      Shell.new(env: environment.merge(env), chdir: chdir, timeout: timeout)
        .run("bundle", "exec", "ruby", File.join(path, "exe", "kimera"), *)
    end

    def script(*, chdir:, stdin:)
      Shell.new(env: environment, chdir: chdir, timeout: LIMIT, input: stdin)
        .run("bundle", "exec", "ruby", "-I#{File.join(path, "lib")}", *)
    end

    def environment = { "BUNDLE_GEMFILE" => gemfile, "KIMERA_PATH" => path, "NO_COLOR" => "1" }

    private

    def shell = Shell.new(env: { "BUNDLE_GEMFILE" => gemfile }, chdir: path, timeout: LIMIT)
  end
end
