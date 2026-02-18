# frozen_string_literal: true

class Api::V1::Accounts::Integrations::AgentosController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_hook

  def agents
    render_response(agentos_client.list_agents)
  end

  def teams
    render_response(agentos_client.list_teams)
  end

  private

  def fetch_hook
    hook_id = params[:hook_id]
    render json: { error: 'Specify hook_id' }, status: :unprocessable_entity if hook_id.blank? && return

    @hook = Current.account.hooks.find_by!(id: hook_id, app_id: 'agentos')
  end

  def agentos_client
    Integrations::Agentos::Client.new(
      base_url: @hook.settings['base_url'],
      security_key: @hook.settings['security_key'],
      tenant_id: @hook.settings['tenant_id']
    )
  end

  def render_response(response)
    if response.is_a?(Hash) && response.with_indifferent_access[:error].present?
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: response, status: :ok
    end
  end
end

