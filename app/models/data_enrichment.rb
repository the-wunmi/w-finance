class DataEnrichment < ApplicationRecord
  belongs_to :enrichable, polymorphic: true

  enum :source, { rule: "rule", external: "external", synth: "synth", ai: "ai" }
end
