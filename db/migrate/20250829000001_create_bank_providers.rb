class CreateBankProviders < ActiveRecord::Migration[7.1]
  def change
    create_table :bank_providers do |t|
      t.string :bank_id, null: false
      t.string :name, null: false
      t.string :display_name
      t.string :country_code, limit: 2, null: false

      t.string :website
      t.string :logo_url

      t.string :primary_color
      t.json :mfa_config
      t.json :credential_fields
      t.json :connection_config
      t.json :ui_config
      t.boolean :active, default: true


      t.timestamps
    end

    add_index :bank_providers, :bank_id, unique: true
    add_index :bank_providers, [ :country_code, :active ]
  end
end
