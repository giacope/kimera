# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::LoadPath
  ROOTS = %w[test spec].freeze
  VARIABLE = "KIMERA_LOAD_PATH"

  def initialize(files, root: ".", env: ENV)
    @files = Array(files)
    @root = root
    @env = env
  end

  def dirs = [*extra.map { |dir| File.expand_path(dir, base) }, *nearest, *top].uniq

  def flags = dirs.flat_map { |dir| ["-I", relative(dir)] }

  def install
    dirs.reverse_each { |dir| $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir) }
  end

  private

  def base = File.expand_path(@root)

  def extra = @env.fetch(VARIABLE, "").split(File::PATH_SEPARATOR)

  def nearest
    @files.flat_map do |file|
      parts = File.expand_path(file, base).split(File::SEPARATOR)
      ROOTS.filter_map { |name| parts.rindex(name)&.then { |index| parts[0..index].join(File::SEPARATOR) } }
    end
  end

  def top = ROOTS.map { |name| File.join(base, name) }.select { |dir| File.directory?(dir) }

  def relative(dir) = dir == base ? "." : dir.delete_prefix("#{base}#{File::SEPARATOR}")
end
