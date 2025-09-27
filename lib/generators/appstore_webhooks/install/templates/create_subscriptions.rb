class CreateSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :subscriptions, id: :uuid do |t|
      t.references :user, null: false, type: :uuid
      t.string :original_transaction_id, null: false
      t.string :app_account_token, null: false
      t.string :product_id
      t.string :status, null: false, default: 'active'
      t.boolean :auto_renew_status
      t.datetime :expires_at
      t.datetime :grace_period_expires_at
      t.datetime :last_synced_at
      t.string :environment, null: false, default: 'sandbox'

      t.timestamps
    end

    add_index :subscriptions, :original_transaction_id, unique: true
    add_index :subscriptions, :app_account_token
    add_index :subscriptions, :status
  end
end
