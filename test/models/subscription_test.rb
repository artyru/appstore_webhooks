# frozen_string_literal: true

require 'test_helper'

class SubscriptionTest < ActiveSupport::TestCase
  def test_requires_original_transaction_id
    user = create_user
    subscription = AppstoreWebhooks::Subscription.new(
      user: user,
      original_transaction_id: nil,
      app_account_token: user.app_account_token,
      product_id: 'product.basic'
    )

    assert_not subscription.valid?
    assert_includes subscription.errors[:original_transaction_id], "can't be blank"
  end
end
