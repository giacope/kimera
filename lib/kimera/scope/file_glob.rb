# frozen_string_literal: true

class Kimera::FileSet::Glob
  def initialize(pattern)
    @pattern = pattern
  end

  def found
    matched = files.sort
    File.file?(@pattern) ? matched : matched.reject { |file| Kimera::ForeignFile.new(file).foreign? }
  end

  def covers?(file) = held.include?(file) || File.fnmatch?(@pattern, file, File::FNM_PATHNAME)

  private

  def held = @_held ||= files.to_set

  def files
    return Dir.glob(File.join(@pattern, "**", "*.rb")) if File.directory?(@pattern)
    Dir.glob(@pattern).select { |f| File.file?(f) && f.end_with?(".rb") }
  end
end
