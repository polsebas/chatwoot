# frozen_string_literal: true

class PendingAgentResponses::CorrectService
  pattr_initialize [:pending_agent_response!, :correction_context!]

  def perform
    hook = pending_agent_response.hook
    conversation = pending_agent_response.conversation
    last_incoming = conversation.messages.incoming.last

    raise ArgumentError, 'No incoming message to correct' if last_incoming.blank?
    raise ArgumentError, 'Hook not found' if hook.blank?

    correction_content = "[Corrección del supervisor]: #{correction_context}"
    pending_agent_response.destroy!

    Integrations::Agentos::ProcessorService.new(
      event_name: 'message.created',
      hook: hook,
      event_data: { message: last_incoming, correction_content: correction_content }
    ).perform
  end
end
