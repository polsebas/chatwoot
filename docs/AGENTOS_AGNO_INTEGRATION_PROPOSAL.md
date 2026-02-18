# Feature Proposal: Agno AgentOS Integration

**Integration with [Agno AgentOS](https://docs.agno.com/agent-os/introduction)** to read agents and teams from an external AgentOS instance and use them in Chatwoot (e.g. for routing, display, or AI-powered flows).

---

## 1. Problem / Motivation

- **Chatwoot** manages its own **teams** and **agents** (users with roles in an account). There is no way to pull in **agents and teams** from an external AI agent runtime.
- Teams that already run **Agno AgentOS** (multi-agent runtime with REST API) cannot reuse their AgentOS agents/teams inside Chatwoot. They have to duplicate configuration or cannot surface AI agents as first-class entities in the support desk.
- Use cases: route conversations to an AI agent, show “available agents” from AgentOS in the dashboard, or sync AgentOS teams with Chatwoot teams for hybrid human + AI workflows.

---

## 2. Proposed Solution

Add an **optional integration** so Chatwoot can **read** from an Agno AgentOS instance:

- **Configure** an AgentOS base URL (and optional auth) per account or globally.
- **Fetch** agents and teams from AgentOS via its REST API (list/get endpoints).
- **Expose** that data to Chatwoot (e.g. API, settings UI, or sync into Chatwoot’s team/agent model for assignment and display).

Implementation can be phased: start with **read-only** (fetch + display or API), then optionally add **sync** or **routing** (e.g. assign to “AgentOS agent” or use in automation).

---

## 3. Technical Approach

### 3.1 AgentOS API (Agno)

- AgentOS exposes a REST API with **Agents** and **Teams**: list, get, run ([Using the API](https://docs.agno.com/agent-os/using-the-api.md)).
- Client usage: connect with `base_url` (e.g. `http://localhost:7777`), optional `Authorization: Bearer <JWT>` ([AgentOS Client](https://docs.agno.com/agent-os/client/agentos-client.md)).
- Example: `aget_config()` returns available agents; equivalent REST endpoints exist for listing agents and teams.

### 3.2 Chatwoot Side

| Layer | Approach |
|-------|----------|
| **Config** | New env/settings: `AGENTOS_BASE_URL`, optional `AGENTOS_JWT` (or per-account in `Integrations::App` / account settings). |
| **Backend** | New service (e.g. `Integrations::AgentOS::Client`) that calls AgentOS list/get for agents and teams; handle timeouts and errors. |
| **Data** | Option A: Only proxy (API that returns AgentOS data). Option B: Sync into DB (e.g. mapping table or new model for “external agent” / “external team” linked to account). |
| **API** | New internal/account-scoped endpoints, e.g. `GET /api/v1/accounts/:account_id/agentos/agents`, `GET .../agentos/teams`, or include in existing integrations API. |
| **Frontend (optional)** | Settings panel to configure AgentOS URL and (optional) show list of AgentOS agents/teams; optional use in assignment/automation UI later. |

### 3.3 Scope (MVP)

- **In scope:** Read-only integration: configure AgentOS URL (and optional auth), fetch and expose agents and teams (API and/or simple UI).
- **Out of scope (initial):** Running agents (e.g. sending messages to AgentOS), full bidirectional sync, or replacing Chatwoot’s native teams/agents.

### 3.4 Enterprise / Extensibility

- Prefer **configuration + extension points** so Enterprise or forks can add AgentOS-specific UI or routing without hardcoding in OSS.
- If integration is account-scoped, consider `enterprise/` overrides for extra UI or permissions (see [Enterprise development practices](https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38)).

---

## 4. Implementation Phases

| Phase | Deliverable |
|-------|-------------|
| **1** | Config (env or account): `AGENTOS_BASE_URL`, optional auth. |
| **2** | Backend client: HTTP client for AgentOS list agents / list teams (and optionally get config). |
| **3** | API: Endpoints to return AgentOS agents and teams to the dashboard (auth with Chatwoot account token). |
| **4** | (Optional) Settings UI: Panel to set AgentOS URL and display fetched agents/teams. |
| **5** | (Future) Sync or routing: Map AgentOS entities to Chatwoot teams/agents or use in assignment/automation. |

---

## 5. Alternatives Considered

- **No integration:** Keeps Chatwoot simpler but leaves AgentOS users without a way to reuse agents/teams in Chatwoot.
- **Full sync by default:** More complex and opinionated; read-only + optional sync is easier to maintain and review.
- **Third-party middleware:** Pushing integration outside Chatwoot adds operational burden; a first-class optional integration is easier for self-hosted users.

---

## 6. References

- [What is AgentOS?](https://docs.agno.com/agent-os/introduction) – Agno AgentOS overview.
- [AgentOS Client](https://docs.agno.com/agent-os/client/agentos-client.md) – Connect via REST, get config and agents.
- [Using the API](https://docs.agno.com/agent-os/using-the-api.md) – Agents/Teams list, get, run.
- [AgentOS Security](https://docs.agno.com/agent-os/security/overview) – Auth (e.g. JWT) when enabled.

---

## 7. Copy-paste for GitHub Feature Request

When opening a **Feature request** in the Chatwoot repo, you can use the following.

**Is your feature or enhancement related to a problem? Please describe.**

Chatwoot does not integrate with external AI agent runtimes. Teams using Agno AgentOS (https://docs.agno.com/agent-os/introduction) cannot reuse their AgentOS agents and teams inside Chatwoot—e.g. to display them in the dashboard, use them in routing, or keep human and AI agent definitions in sync.

**Describe the solution you'd like.**

Add an optional Agno AgentOS integration so Chatwoot can read from an AgentOS instance:

- Configuration: AgentOS base URL (and optional JWT) per account or via env.
- Backend: Service that calls AgentOS REST API to list agents and teams (list/get).
- API: Endpoints to expose AgentOS agents and teams to the dashboard (e.g. under account or integrations).
- Optional: Settings UI to configure the URL and show fetched agents/teams.

Start read-only (fetch and expose); sync or routing can follow in a later phase.

**Describe alternatives you've considered.**

Leaving integration to third-party middleware (adds ops burden). Doing full sync in v1 (read-only first is simpler to maintain and review).

**Additional context.**

- AgentOS exposes Agents and Teams with list/get (and run) operations: https://docs.agno.com/agent-os/using-the-api.md
- AgentOS Client doc: https://docs.agno.com/agent-os/client/agentos-client.md
- A more detailed implementation plan (phases, scope, Enterprise notes) can be provided in a follow-up comment or linked doc.
