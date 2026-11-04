# frozen_string_literal: true

class Kimera::Execution::BlockMethods; end

class Kimera::Execution::BlockMethods::Held
  def initialize(redefinition, definition, visibility, site)
    @redefinition = redefinition
    @definition = definition
    @visibility = visibility
    @site = site
  end

  def install(file)
    return unless @redefinition.found.include?(@definition)
    @redefinition.reinstall(@site.compiled(file), @visibility)
  end
end
