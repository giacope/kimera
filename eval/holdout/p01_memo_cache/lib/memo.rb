module Memo
  @store = {}

  def self.fetch(key)
    return @store[key] if @store.key?(key)

    @store[key] = yield
  end
end
