# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module FakeFeatures
  def fake_feature(name, body = "")
    Dir.mktmpdir("kimera-feature") do |root|
      path = File.join(root, "#{name}.rb").tap { |file| FileUtils.mkdir_p(File.dirname(file)) }
      File.write(path, body)
      $LOAD_PATH.unshift(root)
      yield(path)
    ensure
      $LOAD_PATH.delete(root)
      $LOADED_FEATURES.delete(path)
    end
  end

  def loaded?(path) = $LOADED_FEATURES.include?(path)
end

RSpec.configure { |config| config.include(FakeFeatures) }
