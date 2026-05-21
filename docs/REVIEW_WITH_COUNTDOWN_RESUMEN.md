# Review with countdown – Resumen de cambios, expectativa y errores

## 1. Cambios aplicados

### Backend

| Archivo | Cambio |
|--------|--------|
| **`app/models/pending_agent_response.rb`** | En `push_event_data` se agregó **`conversation_display_id: conversation.display_id`** para que el evento envíe el identificador que usa el dashboard (display_id), no solo el id de base de datos. |
| **`lib/integrations/agentos/processor_service.rb`** | Ya existía: con `response_mode == 'review_with_countdown'` se llama a `create_pending_agent_response` en lugar de crear mensaje directo; timeout 600s para `talkToAgent`. |
| **`app/listeners/action_cable_listener.rb`** | Sin cambios en esta feature: `agent_response_pending` hace broadcast a `user_tokens(account, conversation.inbox.members)` (inbox members + admins del account). |

### Frontend

| Archivo | Cambio |
|--------|--------|
| **`app/javascript/dashboard/helper/actionCable.js`** | En `onAgentResponsePending` se usa **`data.conversation_display_id ?? data.conversation_id`** como clave para guardar el pending en el store. Así la clave coincide con `currentChat.id` (display_id). |

---

## 2. Comportamiento esperado del flujo “Review with countdown”

1. **Usuario** escribe en el widget → mensaje entrante.
2. **Hook AgentOS** procesa el mensaje; el agente responde (puede tardar hasta 10 min con `talkToAgent`).
3. **Backend** (`ProcessorService`):
   - Si `response_mode == 'review_with_countdown'`:
     - **No** se crea mensaje saliente.
     - Se crea un **PendingAgentResponse** con `expires_at` = ahora + `review_countdown_seconds` (por defecto 30 s).
     - Se dispara el evento **`agent_response.pending`** con `pending_agent_response`.
   - Si `response_mode == 'auto'`: se crea el mensaje saliente directo y el widget lo ve.
4. **ActionCable** (`ActionCableListener#agent_response_pending`):
   - Envía el evento solo a **inbox members + administradores del account**.
   - Payload = `pending.push_event_data` (incluye `conversation_display_id` desde el cambio).
5. **Dashboard (frontend)**:
   - Si recibe el evento: guarda en `pendingAgentResponses[conversation_display_id]`.
   - El panel se muestra cuando `getPendingAgentResponse(currentChat.id)` devuelve algo (y `currentChat.id` es display_id).
   - Al abrir la conversación se hace **GET** `.../conversations/:conversation_id/pending_agent_response` (con display_id en la URL) y, si hay pending activo, se rellena el store.
6. **Agente humano** en el dashboard: ve el panel con countdown, puede **Enviar** (approve), **Corregir** o **Descartar**. Solo al aprobar se crea el mensaje y el contacto lo ve.

---

## 3. Errores / por qué no se ve el panel ni el countdown

### A) Clave de conversación (display_id vs id de BD) – **corregido**

- **Problema:** El evento mandaba `conversation_id` (id de BD). El dashboard identifica conversaciones por **display_id** (`currentChat.id`). El store guardaba por id de BD y el getter buscaba por display_id → nunca coincidía.
- **Solución aplicada:** Incluir `conversation_display_id` en el evento y usar esa clave en el frontend.

### B) Broadcast: quién recibe el evento

- El evento **solo** se envía a:
  - **Miembros del inbox** de esa conversación (`conversation.inbox.members`).
  - **Administradores del account** (`account.administrators`).
- Si el usuario que tiene abierto el dashboard **no** es admin y **no** está en `inbox.members`, **no recibe** el evento por ActionCable. En ese caso el panel no aparecerá por WebSocket, pero sí podría verse al abrir la conversación si el GET de pending devuelve datos (si está en la misma cuenta y tiene permiso para ver la conversación).

### C) Expiración del pending (30 s por defecto)

- `PendingAgentResponse` tiene `expires_at` (por defecto 30 s).
- El scope **`active`** filtra `expires_at > Time.current`.
- Si el agente tarda mucho en responder o el usuario abre la conversación **después** de que pasaron 30 s, el GET devuelve 404 y el frontend hace **clear** del pending. Resultado: no se ve panel ni countdown.

### D) API GET al abrir conversación

- Al abrir una conversación se llama a `fetchPendingAgentResponse(conversationId)` con el **display_id** de la URL.
- La API busca la conversación por **display_id** y devuelve `pending_agent_responses.active.last`.
- Si el pending ya expiró o no existe, responde 404 y el store hace **CLEAR** para ese conversationId. Comportamiento correcto, pero implica que si solo confiás en “abrir la conversación después”, el countdown puede haber expirado ya.

### E) Respuesta que “no llega” al widget

- En modo **“Review with countdown”** es **esperado** que la respuesta **no** aparezca en el widget hasta que un agente humano haga **Enviar** en el panel.
- Si se quiere que la respuesta del agente llegue **directo** al widget sin revisión, el modo debe ser **“Automatic”** (`response_mode: 'auto'`).

### F) Posibles fallos de integración

- **AgentOS no responde a tiempo** → no se crea PendingAgentResponse ni mensaje; no hay evento.
- **Error en AgentOS** → `processor_service` hace `return` y no crea pending ni mensaje.
- **WebSocket desconectado** → el evento por ActionCable no llega; solo se vería el pending si se abre la conversación y el GET devuelve un pending aún activo.

---

## 4. Checklist de verificación

- [ ] **Configuración del hook:** `response_mode` = `review_with_countdown` y, si querés, `review_countdown_seconds` > 30 para tener más margen.
- [ ] **Usuario del dashboard:** es **administrador del account** o **miembro del inbox** de esa conversación (para recibir el evento por ActionCable).
- [ ] **Misma conversación:** el panel solo se muestra cuando la conversación activa (`currentChat.id`) es la misma para la que se guardó el pending (por display_id).
- [ ] **Tiempo:** abrir la conversación o tener el dashboard abierto **antes** de que expire el countdown (por defecto 30 s).
- [ ] **API:** probar a mano `GET /api/v1/accounts/:account_id/conversations/:display_id/pending_agent_response` con una conversación que tenga un pending recién creado; debería devolver 200 y el JSON del pending.
- [ ] **Logs Rails:** verificar que no haya errores en `ProcessorService` ni en el listener; opcionalmente loguear en `agent_response_pending` que se hizo el broadcast y a cuántos tokens.
- [ ] **Frontend:** en DevTools → Red o pestaña WebSocket, confirmar que llega un mensaje con `event: 'agent_response.pending'` y que `data.conversation_display_id` está presente cuando se recibe el evento.

---

## 5. Resumen de archivos clave

| Rol | Archivo |
|-----|--------|
| Crear pending y disparar evento | `lib/integrations/agentos/processor_service.rb` |
| Payload del evento (incl. conversation_display_id) | `app/models/pending_agent_response.rb` (#push_event_data) |
| Broadcast por ActionCable | `app/listeners/action_cable_listener.rb` (#agent_response_pending) |
| Recibir evento y guardar en store | `app/javascript/dashboard/helper/actionCable.js` (onAgentResponsePending) |
| Estado y getter | `app/javascript/dashboard/store/modules/conversations/` (index, getters, actions) |
| Panel del countdown | `app/javascript/dashboard/components/widgets/conversation/PendingAgentResponsePanel.vue` |
| Condición de mostrar panel | `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` (v-if pendingAgentResponse && currentChat.id) |
| API GET/approve/correct/discard | `app/controllers/api/v1/accounts/conversations/pending_agent_responses_controller.rb` |

Si después de revisar este checklist el panel sigue sin aparecer, el siguiente paso sería añadir logs temporales en backend (dispatch del evento, broadcast con cantidad de tokens) y en frontend (recepción del evento y valor de `conversation_display_id` / conversationId) para ver en qué paso se corta el flujo.
