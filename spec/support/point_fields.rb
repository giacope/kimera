# frozen_string_literal: true

require "kimera/registry/mutation_point"

module PointFields
  refine Kimera::MutationPoint do
    %i[point_id file operator node_type location original_source method_name mutants ids].each do |field|
      define_method(field) { super() }
    end

    def safe? = fits?(safe: true)
  end
end

using PointFields

module PointRegistry
  def self.of(points, **) = Kimera::Registry.new(files: points.group_by(&:file), **)
end
