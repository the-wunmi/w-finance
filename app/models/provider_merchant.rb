class ProviderMerchant < Merchant
  attribute :source, :string

  enum :source, { external: "external", synth: "synth", ai: "ai" }

  validates :name, uniqueness: { scope: [ :source ] }
  validates :source, presence: true
end
