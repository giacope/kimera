module Plugins
  Plugin = Struct.new(:name, :enabled)

  @all = []

  def self.register(name, enabled: true)
    plugin = Plugin.new(name, enabled)
    @all << plugin
    plugin
  end

  def self.names
    @all.filter_map { |plugin| plugin.name if plugin.enabled }
  end

  def self.count
    @all.count { |plugin| plugin.enabled && !plugin.name.empty? }
  end
end

Plugins.register("core")
