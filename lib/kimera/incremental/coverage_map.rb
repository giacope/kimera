# frozen_string_literal: true

require "fileutils"
require "json"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::CoverageMap
  FORMAT = 2
  NONE = proc { false }

  def self.read(path) = new(JSON.parse(File.read(path, encoding: Encoding::UTF_8)))

  def initialize(document)
    @document = document
  end

  def write(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(@document.merge("format" => FORMAT)))
  end

  def mismatches(current, own = NONE)
    return ["it was stored by another kimera version"] unless @document["format"] == FORMAT
    ruby = @document["ruby"]
    return ["it was measured on #{ruby}, not #{current["ruby"]}"] unless ruby == current["ruby"]
    return ["the settings that pick the tests and sources changed"] unless @document["settings"] == current["settings"]
    drift(@document["files"], current["files"]).reject(&own).first(1).map { |file| "#{file} changed" }
  end

  def picked(current, files, ids, own = NONE)
    wanted = covering(changed(current["sources"]) | files) | written(current, own)
    known = @document["tests"].to_set
    ids.select { |id| wanted.include?(id) || !known.include?(id) }
  end

  def reused(current, picked, total, own = NONE)
    edited = drift(@document["files"], current["files"]).count(&own)
    "kimera: reusing the coverage map from #{commit} (#{changed(current["sources"]).size} source and #{edited} " \
      "test file(s) changed since): the baseline runs #{picked} of #{total} tests"
  end

  private

  def covering(files) = files.flat_map { |file| @document["coverage"].fetch(file, []) }.to_set

  def written(current, own)
    edited = drift(@document["files"], current["files"]).select(&own).to_set
    @document.fetch("test_files", {}).filter_map { |id, file| id if edited.include?(file) }.to_set
  end

  def changed(sources) = drift(@document["sources"], sources)

  def commit = @document["commit"].to_s[0, 7]

  def drift(stored, current) = (stored.keys | current.keys).sort.reject { |path| stored[path] == current[path] }
end
