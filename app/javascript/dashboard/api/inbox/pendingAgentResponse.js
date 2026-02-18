/* global axios */
import ApiClient from '../ApiClient';

class PendingAgentResponseApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get(conversationId) {
    return axios.get(`${this.url}/${conversationId}/pending_agent_response`);
  }

  approve(conversationId, id) {
    return axios.post(
      `${this.url}/${conversationId}/pending_agent_responses/${id}/approve`
    );
  }

  correct(conversationId, id, correctionContext) {
    return axios.post(
      `${this.url}/${conversationId}/pending_agent_responses/${id}/correct`,
      { correction_context: correctionContext }
    );
  }

  discard(conversationId, id) {
    return axios.post(
      `${this.url}/${conversationId}/pending_agent_responses/${id}/discard`
    );
  }
}

export default new PendingAgentResponseApi();
