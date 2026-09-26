# frozen_string_literal: true

require_relative "warnings"

Kimera::Warnings.silence { require "unparser" }

module Kimera
  module Unparse
    module_function

    def parse(source) = Kimera::Warnings.silence { Unparser.parse(source) }

    def unparse(node) = Kimera::Warnings.silence { Unparser.unparse(node) }
  end
end
