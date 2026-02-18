<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  pending: {
    type: Object,
    required: true,
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['approved', 'corrected', 'discarded']);

const store = useStore();

const { t } = useI18n();

const countdown = ref(0);
const showCorrectInput = ref(false);
const correctionContext = ref('');
const loading = ref(false);
let timerId = null;

const isExpired = computed(() => countdown.value <= 0);
const canAct = computed(() => !isExpired.value && !loading.value);

const updateCountdown = () => {
  if (!props.pending?.expires_at) return;
  const expiresAt = new Date(props.pending.expires_at).getTime();
  const now = Date.now();
  countdown.value = Math.max(0, Math.ceil((expiresAt - now) / 1000));
};

const startTimer = () => {
  updateCountdown();
  timerId = setInterval(updateCountdown, 1000);
};

const stopTimer = () => {
  if (timerId) {
    clearInterval(timerId);
    timerId = null;
  }
};

onMounted(() => {
  startTimer();
});

onUnmounted(() => {
  stopTimer();
});

const approve = async () => {
  if (!canAct.value) return;
  loading.value = true;
  try {
    await store.dispatch('approvePendingAgentResponse', {
      conversationId: props.conversationId,
      id: props.pending.id,
    });
    emit('approved');
  } finally {
    loading.value = false;
  }
};

const correct = async () => {
  if (!canAct.value || !correctionContext.value.trim()) return;
  loading.value = true;
  try {
    await store.dispatch('correctPendingAgentResponse', {
      conversationId: props.conversationId,
      id: props.pending.id,
      correctionContext: correctionContext.value.trim(),
    });
    showCorrectInput.value = false;
    correctionContext.value = '';
    emit('corrected');
  } finally {
    loading.value = false;
  }
};

const discard = async () => {
  if (loading.value) return;
  loading.value = true;
  try {
    await store.dispatch('discardPendingAgentResponse', {
      conversationId: props.conversationId,
      id: props.pending.id,
    });
    emit('discarded');
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <div
    class="pending-agent-response-panel rounded-lg border border-n-weak bg-n-alpha-3 p-4 mb-3"
  >
    <p class="text-sm font-medium text-n-slate-12 mb-2">
      {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.TITLE') }}
    </p>
    <div
      class="text-n-slate-11 text-sm whitespace-pre-wrap mb-3 p-2 rounded bg-n-alpha-5 max-h-32 overflow-y-auto"
    >
      {{ pending.content }}
    </div>
    <div class="flex items-center gap-2 flex-wrap">
      <span
        v-if="!isExpired"
        class="text-xs text-n-slate-11"
        :class="{ 'text-n-error': countdown <= 10 }"
      >
        {{
          t('CONVERSATION.PENDING_AGENT_RESPONSE.COUNTDOWN', {
            seconds: countdown,
          })
        }}
      </span>
      <span v-else class="text-xs text-n-slate-11">
        {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.EXPIRED') }}
      </span>
      <div class="flex gap-2 ml-auto">
        <Button
          v-if="!showCorrectInput"
          size="small"
          color="primary"
          :disabled="!canAct"
          :loading="loading"
          @click="approve"
        >
          {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.SEND') }}
        </Button>
        <template v-if="!showCorrectInput">
          <Button
            size="small"
            color="secondary"
            :disabled="!canAct"
            :loading="loading"
            @click="showCorrectInput = true"
          >
            {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.CORRECT') }}
          </Button>
          <Button
            size="small"
            color="secondary"
            :loading="loading"
            @click="discard"
          >
            {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.DISCARD') }}
          </Button>
        </template>
      </div>
    </div>
    <div v-if="showCorrectInput" class="mt-3">
      <textarea
        v-model="correctionContext"
        class="w-full rounded border border-n-weak p-2 text-sm min-h-[60px]"
        :placeholder="
          t('CONVERSATION.PENDING_AGENT_RESPONSE.CORRECTION_PLACEHOLDER')
        "
        rows="2"
      />
      <div class="flex gap-2 mt-2">
        <Button
          size="small"
          color="primary"
          :disabled="!correctionContext.trim() || !canAct"
          :loading="loading"
          @click="correct"
        >
          {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.SEND_CORRECTION') }}
        </Button>
        <Button
          size="small"
          color="secondary"
          :disabled="loading"
          @click="
            showCorrectInput = false;
            correctionContext = '';
          "
        >
          {{ t('CONVERSATION.PENDING_AGENT_RESPONSE.CANCEL') }}
        </Button>
      </div>
    </div>
  </div>
</template>
