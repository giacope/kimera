# frozen_string_literal: true

require "prism"

module Kimera
  class SuperclassPin
    Existing =
      Data.define(:scope, :name) do
        def superclass
          owner = scope.is_a?(Module) ? scope : Object
          inherit = false
          return unless owner.const_defined?(name, inherit)
          found = owner.const_get(name, inherit)
          found.superclass if found.is_a?(Class)
        end
      end

    def initialize(source)
      @source = source
    end

    def pinned
      classes(Prism.parse(@source).value).reverse_each.with_object(@source.b) do |node, text|
        location = node.superclass.location
        text[location.start_offset, location.length] = reopened(node)
      end.force_encoding(@source.encoding)
    end

    private

    def reopened(node)
      path = node.constant_path
      "(::Kimera::SuperclassPin::Existing.new(#{owner(path)}, :#{path.name}).superclass || #{node.superclass.slice})".b
    end

    def owner(path)
      return "::Module.nesting.first" if path.is_a?(Prism::ConstantReadNode)
      path.parent&.slice || "::Object"
    end

    def classes(node)
      (node.is_a?(Prism::ClassNode) && node.superclass ? [node] : []) +
        node.compact_child_nodes.flat_map { |child| classes(child) }
    end
  end
end
