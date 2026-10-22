# frozen_string_literal: true

require "fileutils"
require "json"

module Kimera
  module Incremental
  end
end

# A full baseline's coverage, by source file: which tests reached it, beside
# the fingerprint it was measured against and every test the suite held.
class Kimera::Incremental::CoverageMap
  FORMAT = 1

  def self.read(path) = new(JSON.parse(File.read(path, encoding: Encoding::UTF_8)))

  def initialize(document)
    @document = document
  end

  def write(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(@document.merge("format" => FORMAT)))
  end

  def mismatch(current)
    return "it was stored by another kimera version" unless @document["format"] == FORMAT
    ruby = @document["ruby"]
    return "it was measured on #{ruby}, not #{current["ruby"]}" unless ruby == current["ruby"]
    return "the settings that pick the tests and sources changed" unless @document["settings"] == current["settings"]
    file = drift(@document["files"], current["files"])
    "#{file} changed" if file
  end

  def changed(sources) = drift_all(@document["sources"], sources)

  def tests(files, ids)
    covering = files.flat_map { |file| @document["coverage"].fetch(file, []) }.to_set
    known = @document["tests"].to_set
    ids.select { |id| covering.include?(id) || !known.include?(id) }
  end

  def commit = @document["commit"].to_s[0, 7]

  private

  def drift(stored, current) = drift_all(stored, current).first

  def drift_all(stored, current) = (stored.keys | current.keys).sort.reject { |path| stored[path] == current[path] }
end
