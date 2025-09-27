class CreateSubscriptionEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :subscription_events, id: :uuid do |t|
      t.references :subscription, null: false, type: :uuid, foreign_key: true
      t.references :webhook_notification,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :appstore_webhook_notifications }
      t.string :previous_status
      t.string :next_status, null: false
      t.datetime :effective_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :subscription_events, :effective_at
  end
end
