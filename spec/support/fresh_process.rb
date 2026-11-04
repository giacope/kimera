# frozen_string_literal: true

require "open3"
require "rbconfig"

# A Ruby process started afresh with this checkout's bundle and lib: it has
# loaded nothing the spec run has, so what it prints shows what a file loads.
module FreshProcess
  # The lines a fresh process prints running +script+ in +dir+ (by default the checkout).
  def fresh_lines(script, dir = checkout)
    bundle = { "BUNDLE_GEMFILE" => File.join(checkout, "Gemfile") }
    Open3.capture2(bundle, RbConfig.ruby, "-rbundler/setup", "-I", File.join(checkout, "lib"), "-e", script, chdir: dir)
      .first.lines(chomp: true)
  end

  def checkout = File.expand_path("../..", __dir__)
end

RSpec.configure { |config| config.include(FreshProcess) }
