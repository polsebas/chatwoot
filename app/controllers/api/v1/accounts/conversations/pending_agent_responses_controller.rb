# frozen_string_literal: true

class Api::V1::Accounts::Conversations::PendingAgentResponsesController < Api::V1::Accounts::Conversations::BaseController
  before_action :set_pending_agent_response, only: [:approve, :correct, :discard]

  # GET /api/v1/accounts/:account_id/conversations/:conversation_id/pending_agent_response
  # Returns the active (non-expired) pending agent response for the conversation, if any.
  def show
    @pending = @conversation.pending_agent_responses.active.last
    return head :not_found if @pending.blank?

    authorize @pending, :show?
    render json: @pending.push_event_data
  end

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/pending_agent_responses/:id/approve
  def approve
    authorize @pending_agent_response, :approve?
    message = PendingAgentResponses::ApproveService.new(pending_agent_response: @pending_agent_response).perform
    render json: message.push_event_data, status: :ok
  end

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/pending_agent_responses/:id/correct
  def correct
    authorize @pending_agent_response, :correct?
    correction_context = params.require(:correction_context).to_s
    PendingAgentResponses::CorrectService.new(
      pending_agent_response: @pending_agent_response,
      correction_context: correction_context
    ).perform
    head :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/conversations/:conversation_id/pending_agent_responses/:id/discard
  def discard
    authorize @pending_agent_response, :discard?
    @pending_agent_response.destroy!
    head :no_content
  end

  private

  def set_pending_agent_response
    @pending_agent_response = @conversation.pending_agent_responses.find(params[:id])
  end
end
