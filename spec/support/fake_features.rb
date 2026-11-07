# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module FakeFeatures
  def fake_feature(name, body = "")
    root = Dir.mktmpdir("kimera-feature")
    path = File.join(root, "#{name}.rb").tap { |file| FileUtils.mkdir_p(File.dirname(file)) }
    File.write(path, body)
    $LOAD_PATH.unshift(root)
    faked.push([root, path])
    path
  end

  def loaded?(path) = $LOADED_FEATURES.include?(path)

  private

  def faked = @_faked ||= []
end

RSpec.configure do |config|
  config.include(FakeFeatures)
  config.after do
    faked.each do |root, path|
      $LOAD_PATH.delete(root)
      $LOADED_FEATURES.delete(path)
      FileUtils.remove_entry(root)
    end
  end
end
