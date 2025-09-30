# frozen_string_literal: true

class DictionaryWordPolicy < ApplicationPolicy
  def generate?
    AppstoreWebhooks::Entitlements::Checker.call(user: user, feature: :dictionary_words)
  end
end
