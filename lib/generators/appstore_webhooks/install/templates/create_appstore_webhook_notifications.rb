class CreateAppstoreWebhookNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :appstore_webhook_notifications, id: :uuid do |t|
      t.string :notification_type, null: false
      t.string :subtype
      t.string :notification_uuid, null: false
      t.string :app_account_token
      t.jsonb :raw_payload, null: false, default: {}
      t.jsonb :transaction_payload, null: false, default: {}
      t.jsonb :renewal_payload, null: false, default: {}
      t.string :processing_state, null: false, default: 'pending'
      t.string :processing_error
      t.references :subscription, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :appstore_webhook_notifications, :notification_uuid, unique: true
    add_index :appstore_webhook_notifications, :app_account_token
    add_index :appstore_webhook_notifications, :notification_type
    add_index :appstore_webhook_notifications, :processing_state
  end
end
