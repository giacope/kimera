# frozen_string_literal: true

require_relative "syntax"

module Kimera
  module Syntax
    class Document
      def initialize(root, file)
        @root = root
        @file = file
      end

      def result
        path = File.join(root, file)
        Kimera::Syntax.parse(File.file?(path) ? File.read(path, encoding: Encoding::UTF_8) : "")
      end

      private

      attr_reader :root, :file
    end
  end
end
