# frozen_string_literal: true

require "kimera/registry/mutation_point"

# The fields of a mutation point, which the point keeps to itself, for a spec
# that reads them: `using PointFields` at the top of its file.
module PointFields
  refine Kimera::MutationPoint do
    %i[point_id file operator node_type location original_source method_name mutants ids].each do |field|
      define_method(field) { super() }
    end

    def safe? = fits?(safe: true)
  end
end

using PointFields

# A registry of the points a spec built by hand, filed under their files the
# way a scan files them.
module PointRegistry
  def self.of(points, **) = Kimera::Registry.new(files: points.group_by(&:file), **)
end
