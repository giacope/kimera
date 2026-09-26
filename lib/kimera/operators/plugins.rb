# frozen_string_literal: true

require_relative "../error"
require_relative "../operators"

module Kimera
  module Plugins
    module_function

    def load!(paths, root: ".")
      Array(paths).each { |path| pull(path, root) }
      Kimera::Operators.custom
    end

    def pull(path, root)
      require(resolve(path, root))
    rescue Kimera::Error
      raise
    rescue ScriptError, StandardError => error
      raise(UsageError, "cannot load #{path}: #{error.class}: #{error.message}")
    end

    def resolve(path, root)
      File.expand_path(path, File.expand_path(root))
    end
  end
end
