# frozen_string_literal: true

# Stores a proposed agent response awaiting admin approval (human-in-the-loop).
# When response_mode is +review_with_countdown+, the agent does not create a Message
# immediately; instead a PendingAgentResponse is created and broadcast to the dashboard.
# == Schema Information
#
# Table name: pending_agent_responses
#
#  id              :bigint           not null, primary key
#  content         :text             not null
#  expires_at      :datetime         not null
#  metadata        :jsonb
#  source          :string           default("agentos"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  hook_id         :bigint
#  inbox_id        :bigint           not null
#
# Indexes
#
#  index_pending_agent_responses_on_account_id               (account_id)
#  index_pending_agent_responses_on_conversation_created_at  (conversation_id,created_at)
#  index_pending_agent_responses_on_conversation_id          (conversation_id)
#  index_pending_agent_responses_on_hook_id                  (hook_id)
#  index_pending_agent_responses_on_inbox_id                 (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (hook_id => integrations_hooks.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class PendingAgentResponse < ApplicationRecord
  belongs_to :conversation
  belongs_to :account
  belongs_to :inbox
  belongs_to :hook, class_name: 'Integrations::Hook', optional: true

  validates :content, presence: true
  validates :source, presence: true
  validates :expires_at, presence: true

  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }

  def expired?
    expires_at <= Time.current
  end

  def countdown_seconds
    return 0 if expired?

    (expires_at - Time.current).ceil
  end

  def push_event_data
    {
      id: id,
      conversation_id: conversation_id,
      conversation_display_id: conversation.display_id,
      account_id: account_id,
      content: content,
      source: source,
      expires_at: expires_at.iso8601,
      countdown_seconds: countdown_seconds,
      metadata: metadata || {},
      created_at: created_at.iso8601
    }
  end
end
