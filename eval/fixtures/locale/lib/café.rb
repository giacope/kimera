# Prix en euros — « menu du jour »
module Café
  def self.libellé(prix)
    prix > 10 ? "cher — #{prix} €" : "abordable ✓"
  end
end
