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
        @click="editPrompt(p)"
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

    <div v-if="showLog" class="run-log">
      <div class="run-log-status">
        <span v-if="isRunning" class="status-running">⏳ Running…</span>
        <span v-else-if="runFinalStatus === 'done'" class="status-done">✓ Done</span>
        <span v-else-if="runFinalStatus === 'failed'" class="status-failed">✗ Failed</span>
      </div>
      <div v-if="runFinalStatus === 'failed' && runFailReason" class="run-fail-reason">
        {{ runFailReason }}
      </div>
      <div class="run-log-entries" ref="logEl">
        <div v-for="(line, i) in liveLog" :key="i" class="run-log-line">{{ line }}</div>
      </div>
    </div>

    <div v-if="targetType === 'element' && selectedElement" class="element-edit">
      <div v-if="selectedElement && ['text', 'title'].includes(selectedElement.element_type)" class="content-editor">
        <label class="editor-label">Content</label>
        <textarea
          v-model="elementContent"
          class="content-textarea"
          rows="4"
          placeholder="Edit element content..."
          @blur="saveElementContent"
        ></textarea>
      </div>
      <button class="btn-secondary btn-danger" @click="deleteElement">
        Delete element
      </button>
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
import { ref, computed, watch, nextTick, type PropType } from "vue";
import type { PromptEntry, ElementItem } from "../api";

const props = defineProps({
  selectionLabel: { type: String, default: "" },
  targetType: { type: String, default: "" },
  targetId: { type: String, default: "" },
  bookId: { type: String, default: "" },
  prompts: { type: Array as PropType<PromptEntry[]>, default: () => [] },
  isRunning: { type: Boolean, default: false },
  liveLog: { type: Array as PropType<string[]>, default: () => [] },
  runFinalStatus: { type: String as PropType<"idle" | "done" | "failed">, default: "idle" },
  runFailReason: { type: String, default: "" },
  selectedElement: { type: Object as PropType<ElementItem | null>, default: null },
});

const showLog = computed(() => props.isRunning || props.runFinalStatus !== "idle");
const logEl = ref<HTMLElement | null>(null);

watch(
  () => props.liveLog.length,
  () => nextTick(() => { if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight })
);

const emit = defineEmits<{
  close: [];
  submit: [prompt: string, targetType: string, targetId: string];
  delete: [targetId: string];
  updateContent: [elementId: string, content: string];
}>();

const input = ref("");
const elementContent = ref("");

watch(
  () => props.targetId,
  () => {
    input.value = "";
    elementContent.value = "";
  }
);

watch(
  () => props.selectedElement,
  (el) => {
    if (el && el.content) {
      elementContent.value = el.content;
    } else {
      elementContent.value = "";
    }
  }
);

function submit() {
  const text = input.value.trim();
  if (!text) return;
  emit("submit", text, props.targetType, props.targetId);
  input.value = "";
}

function editPrompt(p: PromptEntry) {
  input.value = p.user_prompt;
}

function deleteElement() {
  emit("delete", props.targetId);
}

function saveElementContent() {
  if (props.selectedElement && elementContent.value !== (props.selectedElement.content || "")) {
    emit("updateContent", props.selectedElement.id, elementContent.value);
  }
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
  cursor: pointer;
  transition: border-color 0.15s;
}

.history-item:hover {
  border-color: var(--primary);
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

.run-log {
  border-top: 1px solid var(--border);
  padding: 10px 16px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.run-log-status {
  font-size: 12px;
  font-weight: 600;
}

.status-running {
  color: var(--text-muted);
}

.status-done {
  color: #4caf50;
}

.status-failed {
  color: #f44336;
}

.run-fail-reason {
  font-size: 11px;
  color: #f44336;
  line-height: 1.4;
  word-break: break-word;
}

.run-log-entries {
  max-height: 160px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.run-log-line {
  font-size: 11px;
  font-family: monospace;
  color: var(--text-muted);
  white-space: pre;
  line-height: 1.5;
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

.element-actions {
  padding: 8px 16px;
  border-top: 1px solid var(--border);
  flex-shrink: 0;
}

.btn-secondary {
  background: var(--card-bg);
  border: 1px solid var(--border);
  color: var(--text);
  padding: 8px 12px;
  border-radius: var(--radius);
  font-size: 13px;
  cursor: pointer;
  transition: border-color 0.15s, color 0.15s;
}

.btn-secondary:hover:not(:disabled) {
  border-color: var(--primary);
  color: var(--primary);
}

.btn-secondary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-danger {
  border-color: #f44336;
  color: #f44336;
}

.btn-danger:hover:not(:disabled) {
  border-color: #d32f2f;
  color: #d32f2f;
  background: rgba(244, 67, 54, 0.05);
}

.element-edit {
  padding: 12px 16px;
  border-top: 1px solid var(--border);
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.content-editor {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.editor-label {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.content-textarea {
  width: 100%;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  font-size: 12px;
  resize: none;
  outline: none;
  background: var(--card-bg);
  color: var(--text);
  font: inherit;
}

.content-textarea:focus {
  border-color: var(--primary);
}
</style>