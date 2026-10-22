# frozen_string_literal: true

require_relative "syntax"

module Kimera
  module SyntaxTypes
    Kimera::Syntax.constants.grep(/Node\z/).each do |name|
      const_set(name, Kimera::Syntax.const_get(name))
    end

    Installer =
      Data.define(:target) do
        def call
          SyntaxTypes.constants.grep(/Node\z/).each do |name|
            target.const_set(name, SyntaxTypes.const_get(name)) unless target.constants.include?(name)
          end
        end
      end
  end
end
