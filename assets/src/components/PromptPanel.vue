<template>
  <aside v-if="selectionLabel" class="prompt-panel">
    <div class="panel-header">
      <h3>{{ selectionLabel }}</h3>
      <button class="btn-ghost close-btn" @click="$emit('close')">×</button>
    </div>

    <div class="prompt-history">
      <div v-if="prompts.length === 0" class="history-empty">
        No prompts yet for this {{ targetType }}.
      </div>
      <div
        v-for="p in prompts"
        :key="p.id"
        class="history-item"
      >
        <div class="history-prompt">{{ p.user_prompt }}</div>
        <div v-if="p.result_summary" class="history-result">
          {{ truncate(p.result_summary, 120) }}
        </div>
        <div class="history-meta">
          {{ formatDate(p.created_at) }}
        </div>
      </div>
    </div>

    <div class="prompt-input-area">
      <textarea
        v-model="input"
        placeholder="Describe what to change..."
        @keydown.enter.exact.prevent="submit"
        rows="3"
      ></textarea>
      <button
        class="btn-primary"
        :disabled="isRunning || !input.trim()"
        @click="submit"
      >
        {{ isRunning ? "..." : "Send" }}
      </button>
    </div>
  </aside>
</template>

<script setup lang="ts">
import { ref, watch, type PropType } from "vue";
import type { PromptEntry } from "../api";

const props = defineProps({
  selectionLabel: { type: String, default: "" },
  targetType: { type: String, default: "" },
  targetId: { type: String, default: "" },
  bookId: { type: String, default: "" },
  prompts: { type: Array as PropType<PromptEntry[]>, default: () => [] },
  isRunning: { type: Boolean, default: false },
});

const emit = defineEmits<{
  close: [];
  submit: [prompt: string, targetType: string, targetId: string];
}>();

const input = ref("");

watch(
  () => props.targetId,
  () => { input.value = ""; }
);

function submit() {
  const text = input.value.trim();
  if (!text) return;
  emit("submit", text, props.targetType, props.targetId);
  input.value = "";
}

function truncate(text: string, max: number) {
  if (!text) return "";
  return text.length > max ? text.slice(0, max) + "..." : text;
}

function formatDate(iso: string) {
  if (!iso) return "";
  return new Date(iso + "Z").toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
</script>

<style scoped>
.prompt-panel {
  background: var(--panel-bg);
  border-left: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  height: 100vh;
  width: 320px;
  overflow: hidden;
}

.panel-header {
  padding: 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}

.panel-header h3 {
  font-size: 14px;
  font-weight: 600;
}

.close-btn {
  background: none;
  border: none;
  font-size: 18px;
  color: var(--text-muted);
  padding: 0 4px;
  line-height: 1;
}

.close-btn:hover {
  color: var(--text);
}

.prompt-history {
  flex: 1;
  overflow-y: auto;
  padding: 12px 16px;
}

.history-empty {
  color: var(--text-muted);
  font-size: 13px;
  padding: 24px 0;
  text-align: center;
}

.history-item {
  margin-bottom: 12px;
  padding: 10px 12px;
  background: var(--card-bg);
  border-radius: 6px;
  border: 1px solid var(--border);
}

.history-prompt {
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 4px;
  line-height: 1.4;
}

.history-result {
  font-size: 12px;
  color: var(--text-muted);
  margin-bottom: 4px;
  line-height: 1.3;
}

.history-meta {
  font-size: 11px;
  color: var(--text-muted);
}

.prompt-input-area {
  padding: 12px 16px 16px;
  border-top: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex-shrink: 0;
}

.prompt-input-area textarea {
  width: 100%;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  font-size: 13px;
  resize: none;
  outline: none;
  background: var(--card-bg);
}

.prompt-input-area textarea:focus {
  border-color: var(--primary);
}
</style>