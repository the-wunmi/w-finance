class CreateBankConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :bank_connections do |t|
      t.references :family, null: false
      t.references :bank_provider, null: false
      t.string :status, null: false, default: "pending"
      t.text :credentials
      t.text :session_token
      t.datetime :session_expires_at

      t.timestamps
    end

    add_index :bank_connections, [ :family_id, :bank_provider_id ]
  end
end
