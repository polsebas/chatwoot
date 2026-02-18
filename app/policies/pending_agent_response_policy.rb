# frozen_string_literal: true

class PendingAgentResponsePolicy < ApplicationPolicy
  def show?
    can_access_conversation?
  end

  def approve?
    can_access_conversation?
  end

  def correct?
    can_access_conversation?
  end

  def discard?
    can_access_conversation?
  end

  private

  def can_access_conversation?
    return false unless account && record.conversation

    ConversationPolicy.new(user_context, record.conversation).show?
  end
end
