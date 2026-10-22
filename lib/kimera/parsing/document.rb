# frozen_string_literal: true

require_relative "syntax"

module Kimera
  module Syntax
    # A project file parsed whole; one that is not there parses as an empty program.
    Document =
      Data.define(:root, :file) do
        def result
          path = File.join(root, file)
          Kimera::Syntax.parse(File.file?(path) ? File.read(path, encoding: Encoding::UTF_8) : "")
        end
      end
  end
end
