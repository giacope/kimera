# frozen_string_literal: true

module KimeraEval
  # The kimera checkout under evaluation, run from its own bundle.
  class Checkout
    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
      raise(ArgumentError, "not a kimera checkout: #{@path}") unless File.file?(File.join(@path, "exe", "kimera"))
    end

    def prepare!
      return if shell.run("bundle", "check").ok?
      result = shell.run("bundle", "install")
      raise("bundle install failed in #{@path}:\n#{result.output}") unless result.ok?
    end

    def gemfile = File.join(@path, "Gemfile")

    def revision = shell.run("git", "-C", @path, "rev-parse", "--short", "HEAD").out.strip

    def kimera(*args, chdir:, env: {}, timeout: 900)
      Shell.new(env: environment.merge(env), chdir: chdir, timeout: timeout)
        .run("bundle", "exec", "ruby", File.join(@path, "exe", "kimera"), *args)
    end

    def ruby(*args, chdir:, env: {}, timeout: 900, stdin: nil)
      Shell.new(env: environment.merge(env), chdir: chdir, timeout: timeout, input: stdin)
        .run("bundle", "exec", "ruby", "-I#{File.join(@path, "lib")}", *args)
    end

    def environment = { "BUNDLE_GEMFILE" => gemfile, "KIMERA_PATH" => @path, "NO_COLOR" => "1" }

    private

    def shell = Shell.new(env: { "BUNDLE_GEMFILE" => gemfile }, chdir: @path, timeout: 900)
  end
end
