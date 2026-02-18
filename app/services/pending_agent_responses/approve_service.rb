# frozen_string_literal: true

class PendingAgentResponses::ApproveService
  pattr_initialize [:pending_agent_response!]

  def perform
    conv = pending_agent_response.conversation
    additional_attrs = {}
    additional_attrs[:agent_name] = pending_agent_response.metadata['agent_name'] if pending_agent_response.metadata&.dig('agent_name').present?

    message = conv.messages.create!(
      message_type: :outgoing,
      account_id: conv.account_id,
      inbox_id: conv.inbox_id,
      content: pending_agent_response.content,
      additional_attributes: additional_attrs
    )

    pending_agent_response.destroy!
    message
  end
end
