# frozen_string_literal: true

require_relative "../error"
require_relative "../operators"

module Kimera
  class Plugins
    def initialize(paths, root: ".")
      @paths = paths
      @root = root
    end

    def load!
      Array(@paths).each { |path| pull(path) }
      Kimera::Operators::CATALOG.custom
    end

    private

    def pull(path)
      require(resolve(path))
    rescue Kimera::Error
      raise
    rescue ScriptError, StandardError => error
      raise(UsageError, "cannot load #{path}: #{error.class}: #{error.message}")
    end

    def resolve(path) = File.expand_path(path, File.expand_path(@root))
  end
end
