class DataEnrichment < ApplicationRecord
  belongs_to :enrichable, polymorphic: true

  attribute :source, :string

  enum :source, { rule: "rule", external: "external", synth: "synth", ai: "ai" }
end
