# frozen_string_literal: true

class Integrations::Agentos::Client
  DEFAULT_TIMEOUT = 10
  OPEN_TIMEOUT = 15  # seconds to establish connection; read timeout is set per-request

  def initialize(base_url:, security_key: nil, tenant_id: nil, timeout: DEFAULT_TIMEOUT)
    @base_url = base_url.to_s.strip
    @security_key = security_key.to_s.strip
    @tenant_id = tenant_id.to_s.strip
    @timeout = timeout

    raise ArgumentError, 'Missing base_url' if @base_url.blank?
  end

  # Custom AgentOS deployments may expose a single chat endpoint (eg. CarRentalAI)
  # that triggers an agent run and returns a response synchronously.
  #
  # Expected payload (OpenAPI):
  # - messages (Array<{role, content}>)
  # - sessionId (String)
  # - datos_cliente (Object)
  # Optional:
  # - user_id, ingenieria_contexto, tipo_agente
  def talk_to_agent(messages:, session_id:, customer:, user_id: nil, engineer_context: false, agent_type: nil)
    payload = {
      messages: messages,
      sessionId: session_id,
      datos_cliente: customer,
      user_id: user_id,
      ingenieria_contexto: engineer_context,
      tipo_agente: agent_type
    }.compact

    process_response(post_json('/talkToAgent', payload))
  end

  def list_agents
    process_response(get('/agents'))
  end

  def list_teams
    process_response(get('/teams'))
  end

  def run_agent(agent_id:, message:, user_id: nil, session_id: nil, stream: false, version: nil)
    raise ArgumentError, 'Missing agent_id' if agent_id.blank?
    raise ArgumentError, 'Missing message' if message.blank?

    if tenant_mode? && session_id.present?
      create_session(session_id: session_id, user_id: user_id, agent_id: normalize_target_id(agent_id))
      return run_session_message(session_id: session_id, message: message)
    end

    payload = {
      message: message,
      stream: stream,
      user_id: user_id,
      session_id: session_id,
      version: version
    }.compact

    process_response(post_json("/agents/#{agent_id}/runs", payload))
  end

  def run_team(team_id:, message:, user_id: nil, session_id: nil, stream: false, version: nil)
    raise ArgumentError, 'Missing team_id' if team_id.blank?
    raise ArgumentError, 'Missing message' if message.blank?

    if tenant_mode? && session_id.present?
      create_session(session_id: session_id, user_id: user_id, team_id: normalize_target_id(team_id))
      return run_session_message(session_id: session_id, message: message)
    end

    payload = {
      message: message,
      stream: stream,
      user_id: user_id,
      session_id: session_id,
      version: version
    }.compact

    process_response(post_json("/teams/#{team_id}/runs", payload))
  end

  # Session-based AgentOS API (common in multi-tenant deployments).
  # When `tenant_id` is present, run_* will prefer this API over /runs.
  def create_session(session_id:, user_id: nil, agent_id: nil, team_id: nil, workflow_id: nil, metadata: nil)
    payload = {
      session_id: session_id,
      user_id: user_id,
      team_id: team_id,
      agent_id: agent_id,
      workflow_id: workflow_id,
      metadata: metadata
    }.compact

    process_response(post_json('/sessions/', payload))
  end

  def add_message(session_id:, role:, content:, metadata: nil)
    payload = {
      role: role,
      content: content,
      metadata: metadata
    }.compact

    process_response(post_json("/sessions/#{session_id}/messages", payload))
  end

  def get_messages(session_id:, limit: nil, offset: 0)
    query = { limit: limit, offset: offset }.compact
    process_response(get("/sessions/#{session_id}/messages", query: query))
  end

  private

  def tenant_mode?
    @tenant_id.present?
  end

  def normalize_target_id(target_id)
    normalized = target_id.to_s.strip
    return nil if normalized.blank? || normalized.casecmp('default').zero?

    normalized
  end

  def run_session_message(session_id:, message:)
    message_response = add_message(session_id: session_id, role: 'user', content: message)
    return message_response if error_response?(message_response)

    assistant_content = extract_assistant_content(message_response)
    return { 'content' => assistant_content } if assistant_content.present?

    history = get_messages(session_id: session_id, limit: 20, offset: 0)
    return history if error_response?(history)

    assistant_message = Array(history).reverse.find do |m|
      m.is_a?(Hash) && m['role'] == 'assistant' && m['content'].present?
    end

    assistant_message.present? ? { 'content' => assistant_message['content'] } : nil
  end

  def extract_assistant_content(message_response)
    return nil unless message_response.is_a?(Hash)

    role = message_response['role'] || message_response[:role]
    content = message_response['content'] || message_response[:content]

    role == 'assistant' && content.present? ? content : nil
  end

  def error_response?(response)
    response.is_a?(Hash) && response.with_indifferent_access[:error].present?
  end

  def headers
    base_headers = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }

    if @security_key.present?
      # Some AgentOS deployments expect an API key header instead of Bearer auth.
      base_headers['X-API-Key'] = @security_key
      base_headers['Authorization'] = "Bearer #{@security_key}"
    end
    base_headers['X-Tenant-ID'] = @tenant_id if @tenant_id.present?

    base_headers
  end

  def get(path, query: nil)
    HTTParty.get(
      url(path),
      headers: headers,
      query: query,
      timeout: @timeout,
      open_timeout: OPEN_TIMEOUT
    )
  end

  def post_json(path, payload)
    HTTParty.post(
      url(path),
      headers: headers,
      body: payload.to_json,
      timeout: @timeout,
      open_timeout: OPEN_TIMEOUT
    )
  end

  def url(path)
    base = @base_url.delete_suffix('/')
    normalized_path = path.start_with?('/') ? path : "/#{path}"
    "#{base}#{normalized_path}"
  end

  def process_response(response)
    return response.parsed_response if response.success?

    { error: response.parsed_response, error_code: response.code }
  rescue StandardError => e
    { error: { detail: e.message }, error_code: 500 }
  end
end

