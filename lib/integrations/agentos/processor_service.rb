# frozen_string_literal: true

class Integrations::Agentos::ProcessorService < Integrations::BotProcessorService
  include Events::Types

  pattr_initialize [:event_name!, :hook!, :event_data!]

  # `talkToAgent` can take many minutes for complex agent resolutions (tools, multi-step, etc).
  # Chatwoot must wait for the full response; 10 minutes allows for long-running agent runs.
  TALK_TO_AGENT_TIMEOUT = 600

  def process_content(message)
    content = event_data[:correction_content].presence || message_content(message)
    response = get_response(conversation.contact_inbox.source_id, content) if content.present?
    process_response(message, response) if response.present?
  end

  private

  def get_response(user_id, message_content)
    base_url = hook.settings['base_url']
    tenant_id = hook.settings['tenant_id']
    security_key = hook.settings['security_key']
    target_kind = hook.settings['target_kind']
    target_id = hook.settings['target_id']

    timeout = tenant_id.present? ? TALK_TO_AGENT_TIMEOUT : Integrations::Agentos::Client::DEFAULT_TIMEOUT
    client = Integrations::Agentos::Client.new(
      base_url: base_url,
      security_key: security_key,
      tenant_id: tenant_id,
      timeout: timeout
    )

    response = tenant_id.present? ? try_talk_to_agent(client, user_id, target_id) : nil

    if response.blank? || agentos_not_found_response?(response)
      response =
        if target_kind == 'team'
          client.run_team(
            team_id: target_id,
            message: message_content,
            user_id: user_id,
            session_id: conversation.uuid,
            stream: false
          )
        else
          client.run_agent(
            agent_id: target_id,
            message: message_content,
            user_id: user_id,
            session_id: conversation.uuid,
            stream: false
          )
        end
    end

    return if response.blank?
    if agentos_error_response?(response)
      indifferent = response.with_indifferent_access
      error_code = indifferent[:error_code]
      error_payload = indifferent[:error]
      message_id = event_data[:message]&.id

      Rails.logger.warn(
        "AgentOS Request failed: (account-#{hook.try(:account_id)}, hook-#{hook.id}, inbox-#{hook.inbox_id}, conversation-#{conversation.id}, message-#{message_id}) " \
        "status=#{error_code} error=#{error_payload.to_json.truncate(500)}"
      )

      return
    end

    response
  rescue StandardError => e
    Rails.logger.warn "AgentOS Error: (account-#{hook.try(:account_id)}, hook-#{hook.id}) #{e.message}"
    nil
  end

  def try_talk_to_agent(client, user_id, agent_type)
    client.talk_to_agent(
      messages: build_talk_to_agent_messages,
      session_id: conversation.uuid,
      customer: build_talk_to_agent_customer,
      user_id: user_id,
      engineer_context: false,
      agent_type: normalize_agent_type(agent_type)
    )
  end

  def normalize_agent_type(agent_type)
    normalized = agent_type.to_s.strip
    return nil if normalized.blank? || normalized.casecmp('default').zero?

    normalized
  end

  def build_talk_to_agent_messages
    conversation
      .messages
      .where(private: false)
      .where(message_type: [:incoming, :outgoing])
      .order(:id)
      .last(10)
      .filter_map do |m|
        next if m.content.blank?

        {
          role: m.incoming? ? 'user' : 'assistant',
          content: m.content
        }
      end
  end

  def build_talk_to_agent_customer
    contact = conversation.contact
    contact_custom_attributes = (contact&.custom_attributes || {}).with_indifferent_access
    conversation_custom_attributes = (conversation.custom_attributes || {}).with_indifferent_access

    {
      nombre_completo: (
        contact&.name.presence ||
        contact_custom_attributes[:nombre_completo] ||
        conversation_custom_attributes[:nombre_completo]
      ).to_s,
      fecha_nacimiento: (
        contact_custom_attributes[:fecha_nacimiento] ||
        conversation_custom_attributes[:fecha_nacimiento]
      ).to_s,
      licencia_conducir: (
        contact_custom_attributes[:licencia_conducir] ||
        conversation_custom_attributes[:licencia_conducir]
      ).to_s,
      pais_licencia: (
        contact_custom_attributes[:pais_licencia] ||
        conversation_custom_attributes[:pais_licencia]
      ).to_s,
      pasaporte_dni: (
        contact_custom_attributes[:pasaporte_dni] ||
        conversation_custom_attributes[:pasaporte_dni]
      ).to_s,
      email: (
        contact&.email.presence ||
        contact_custom_attributes[:email] ||
        conversation_custom_attributes[:email]
      ).to_s,
      telefono: (
        contact&.phone_number.presence ||
        contact_custom_attributes[:telefono] ||
        conversation_custom_attributes[:telefono]
      ).to_s,
      tarjeta_credito: '',
      fecha_vencimiento_tarjeta: '',
      cvv_tarjeta: '',
      direccion: (
        contact_custom_attributes[:direccion] ||
        conversation_custom_attributes[:direccion]
      ).to_s
    }
  end

  def extract_content(response)
    return response if response.is_a?(String)

    if response.is_a?(Hash)
      indifferent = response.with_indifferent_access

      return indifferent[:content] if indifferent[:content].present?
      return indifferent[:response] if indifferent[:response].is_a?(String) && indifferent[:response].present?
      return indifferent[:message] if indifferent[:message].is_a?(String) && indifferent[:message].present?
      return indifferent[:answer] if indifferent[:answer].is_a?(String) && indifferent[:answer].present?
      return indifferent[:text] if indifferent[:text].is_a?(String) && indifferent[:text].present?

      from_messages = extract_assistant_content_from_messages(indifferent[:messages])
      return from_messages if from_messages.present?
    end

    from_messages = extract_assistant_content_from_messages(response) if response.is_a?(Array)
    return from_messages if from_messages.present?

    nil
  end

  def extract_assistant_content_from_messages(messages)
    Array(messages).reverse_each do |m|
      next unless m.is_a?(Hash)

      role = m['role'] || m[:role]
      content = m['content'] || m[:content]
      next unless role.to_s == 'assistant'
      next unless content.is_a?(String) && content.present?

      return content
    end

    nil
  end

  def process_response(message, response)
    return if response.blank?

    sync_contact_from_agentos_customer_data(response)

    content = extract_content(response)
    return if content.blank?

    if review_with_countdown?
      create_pending_agent_response(message, content)
    else
      create_conversation(message, { content: content })
    end
  end

  def review_with_countdown?
    hook.settings['response_mode'].to_s == 'review_with_countdown'
  end

  def create_pending_agent_response(message, content)
    conv = message.conversation
    countdown_sec = hook.settings['review_countdown_seconds'].to_i
    countdown_sec = 120 if countdown_sec <= 0
    expires_at = countdown_sec.seconds.from_now

    metadata = {
      trigger_message_id: message.id,
      hook_id: hook.id
    }
    agent_name = response_agent_name(message, content)
    metadata[:agent_name] = agent_name if agent_name.present?

    pending = PendingAgentResponse.create!(
      conversation_id: conv.id,
      account_id: conv.account_id,
      inbox_id: conv.inbox_id,
      content: content,
      source: 'agentos',
      hook_id: hook.id,
      metadata: metadata,
      expires_at: expires_at
    )

    Rails.configuration.dispatcher.dispatch(
      AGENT_RESPONSE_PENDING,
      Time.zone.now,
      pending_agent_response: pending
    )
  end

  def response_agent_name(_message, _content)
    nil
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        }
      )
    )
  end

  def sync_contact_from_agentos_customer_data(response)
    return unless truthy_setting?(hook.settings['sync_contact_attributes'])
    return unless response.is_a?(Hash)

    customer = extract_customer_payload(response)
    return if customer.blank?

    safe_customer_data = sanitize_customer_payload(customer)
    return if safe_customer_data.blank?

    contact = conversation.contact
    return if contact.blank?

    customer_data_to_merge = safe_customer_data.reject { |_k, v| v.blank? }
    return if customer_data_to_merge.blank?

    contact_attributes = {}
    nombre_completo = customer_data_to_merge['nombre_completo'].to_s.strip
    email = customer_data_to_merge['email'].to_s.strip
    telefono = customer_data_to_merge['telefono'].to_s.strip

    contact_attributes[:name] = nombre_completo if contact.name.blank? && nombre_completo.present?
    contact_attributes[:email] = email if contact.email.blank? && email.present? && email.match?(Devise.email_regexp)
    contact_attributes[:phone_number] = telefono if contact.phone_number.blank? && telefono.present? && telefono.match?(/\+[1-9]\d{1,14}\z/)

    contact.assign_attributes(contact_attributes) if contact_attributes.present?

    existing_custom_attributes = (contact.custom_attributes || {}).stringify_keys
    updated_custom_attributes = existing_custom_attributes.dup
    customer_data_to_merge.each do |key, value|
      updated_custom_attributes[key] = value if updated_custom_attributes[key].blank?
    end

    contact.custom_attributes = updated_custom_attributes
    contact.save!
  rescue StandardError => e
    Rails.logger.warn(
      "AgentOS contact sync error: " \
      "(account-#{hook.try(:account_id)}, hook-#{hook.id}, inbox-#{hook.inbox_id}, conversation-#{conversation.id}) " \
      "#{e.message}"
    )
    nil
  end

  def extract_customer_payload(response)
    indifferent = response.with_indifferent_access
    payload =
      indifferent[:datos_cliente] ||
      indifferent[:datosCliente] ||
      indifferent[:customer] ||
      indifferent[:customer_data]
    payload.is_a?(Hash) ? payload : nil
  end

  def sanitize_customer_payload(payload)
    indifferent = payload.with_indifferent_access

    # Never store sensitive card data in Chatwoot.
    unsafe_keys = %i[tarjeta_credito fecha_vencimiento_tarjeta cvv_tarjeta]
    indifferent.except(*unsafe_keys).to_h.stringify_keys
  end

  def truthy_setting?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def agentos_error_response?(response)
    response.is_a?(Hash) && response.with_indifferent_access[:error].present?
  end

  def agentos_not_found_response?(response)
    return false unless agentos_error_response?(response)

    response.with_indifferent_access[:error_code].to_i.in?([404, 405])
  end
end

