# frozen_string_literal: true

module KimeraEval
  class SetupError < StandardError; end

  class Checkout
    LIMIT = 900

    def initialize(path)
      @given = path
    end

    def prepare!
      raise(SetupError, "not a kimera checkout: #{path}") unless File.file?(File.join(path, "exe", "kimera"))
      checked, = shell.run("bundle", "check")
      return if checked.ok?
      installed, printed = shell.run("bundle", "install")
      raise(SetupError, "bundle install failed in #{path}:\n#{printed.output}") unless installed.ok?
    end

    def cli(*, chdir:, env: {}, timeout: LIMIT)
      Shell.new(env: environment.merge(env), chdir: chdir, timeout: timeout)
        .run("bundle", "exec", "ruby", File.join(path, "exe", "kimera"), *)
    end

    def script(*, chdir:, stdin:)
      Shell.new(env: environment, chdir: chdir, timeout: LIMIT, input: stdin)
        .run("bundle", "exec", "ruby", "-I#{File.join(path, "lib")}", *)
    end

    def shell(env: {}, timeout: LIMIT)
      Shell.new(env: { "BUNDLE_GEMFILE" => gemfile }.merge(env), chdir: path, timeout: timeout)
    end

    def to_s = path

    def to_h = { "kimera" => path, "revision" => revision }

    private

    def path = @_path ||= File.expand_path(@given)

    def gemfile = File.join(path, "Gemfile")

    def revision
      _, printed = shell.run("git", "-C", path, "rev-parse", "--short", "HEAD")
      printed.to_s.strip
    end

    def environment = { "BUNDLE_GEMFILE" => gemfile, "KIMERA_PATH" => path, "NO_COLOR" => "1" }
  end
end
