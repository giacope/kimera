# frozen_string_literal: true

require "prism"

module Kimera
  module SuperclassPin
    module_function

    def pin(source)
      classes(Prism.parse(source).value).reverse_each.with_object(source.b) do |node, text|
        location = node.superclass.location
        text[location.start_offset, location.length] = reopened(node)
      end.force_encoding(source.encoding)
    end

    def existing(scope, name)
      owner = scope.is_a?(Module) ? scope : Object
      inherit = false
      return unless owner.const_defined?(name, inherit)
      found = owner.const_get(name, inherit)
      found.superclass if found.is_a?(Class)
    end

    def reopened(node)
      path = node.constant_path
      "(::Kimera::SuperclassPin.existing(#{owner(path)}, :#{path.name}) || #{node.superclass.slice})".b
    end

    def owner(path)
      return "::Module.nesting.first" if path.is_a?(Prism::ConstantReadNode)
      path.parent&.slice || "::Object"
    end

    def classes(node, found = [])
      found << node if node.is_a?(Prism::ClassNode) && node.superclass
      node.compact_child_nodes.each { |child| classes(child, found) }
      found
    end
  end
end
