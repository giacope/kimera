module Tagger
  DEFAULTS = ["base"]

  def self.tags_for(title)
    tags = DEFAULTS.dup
    tags << "long" if title.length > 10
    tags << "question" if title.end_with?("?")
    tags << "shout" if title == title.upcase && title.match?(/[A-Z]/)
    tags
  end
end
