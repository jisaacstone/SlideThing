<template>
  <main class="page-view">
    <div v-if="!page" class="empty-state">
      <p>Select a page from the outline.</p>
    </div>

    <div v-else class="page-content">
      <div v-if="overflowingElements.length > 0" class="overflow-error">
        <span class="overflow-icon">&#9888;</span>
        {{ overflowingElements.length }} element{{ overflowingElements.length !== 1 ? 's' : '' }}
        overflow the page bounds
      </div>

      <div class="page-canvas" :class="{ 'has-overflow': overflowingElements.length > 0 }" :style="canvasStyle" ref="canvasRef">
        <div
          v-for="el in page.elements"
          :key="el.id"
          class="page-element"
          :class="[
            'el-' + el.element_type,
            {
              selectable: true,
              'el-overflows': isOverflowing(el.id),
              'el-dragging': dragState?.elementId === el.id,
              'el-editing': editState?.elementId === el.id,
            },
          ]"
          :style="elementStyle(el)"
          @pointerdown="startDrag($event, el)"
          @pointermove="onDrag($event)"
          @pointerup="endDrag($event)"
          @lostpointercapture="cancelDrag()"
          @dblclick="startEdit($event, el)"
        >
          <div v-if="el.element_type === 'image' && el.asset_path" class="el-image-wrapper">
            <img :src="'/api/assets/' + el.asset_path" alt="" />
          </div>
          <div v-else class="el-text">
            <template v-if="editState?.elementId === el.id">
              <textarea
                :id="`edit-${el.id}`"
                class="el-edit-textarea"
                v-model="editState.content"
                @blur="saveEdit(el)"
                @keydown.esc.prevent="cancelEdit()"
                @keydown.ctrl.enter.prevent="saveEdit(el)"
                @pointerdown.stop
                @click.stop
              />
            </template>
            <template v-else>
              <MarkdownContent v-if="el.content" :content="el.content" />
              <span v-else></span>
            </template>
          </div>
        </div>
      </div>
    </div>
  </main>
</template>

<script setup lang="ts">
import { computed, ref, nextTick } from "vue";
import type { Page, ElementItem } from "../api";
import MarkdownContent from "./MarkdownContent.vue";

const props = defineProps<{
  page: Page | null;
}>();

const emit = defineEmits<{
  "select-element": [elementId: string];
  "move-element": [elementId: string, x: number, y: number];
  "update-content": [elementId: string, content: string];
}>();

const canvasRef = ref<HTMLElement | null>(null);

interface DragState {
  elementId: string;
  pointerId: number;
  startFracX: number;
  startFracY: number;
  startElemX: number;
  startElemY: number;
  currentX: number;
  currentY: number;
  hasMoved: boolean;
}

interface EditState {
  elementId: string;
  content: string;
  originalContent: string;
}

const dragState = ref<DragState | null>(null);
const editState = ref<EditState | null>(null);

// Use the most recent layout (first in the array, sorted newest-first by the API)
const primaryLayout = computed(() => props.page?.layouts?.[0] ?? null);

const format = computed(() => primaryLayout.value?.format ?? null);

// Map element_id -> bounding box fractions
const bboxByElement = computed(() => {
  const map: Record<string, { x: number; y: number; width: number; height: number }> = {};
  for (const item of primaryLayout.value?.element_layouts ?? []) {
    map[item.element_id] = { x: item.x, y: item.y, width: item.width, height: item.height };
  }
  return map;
});

const overflowingElements = computed(() =>
  (props.page?.elements ?? []).filter((el) => isOverflowing(el.id))
);

function isOverflowing(elementId: string): boolean {
  const bb = bboxByElement.value[elementId];
  if (!bb) return false;
  return bb.x < 0 || bb.y < 0 || bb.x + bb.width > 1 || bb.y + bb.height > 1;
}

const canvasStyle = computed(() => {
  if (!format.value) return {};
  return { aspectRatio: `${format.value.width} / ${format.value.height}` };
});

function elementStyle(el: ElementItem): Record<string, string> {
  const bb = bboxByElement.value[el.id];
  if (!bb) return {};

  let x = bb.x;
  let y = bb.y;

  if (dragState.value?.elementId === el.id) {
    x = dragState.value.currentX;
    y = dragState.value.currentY;
  }

  return {
    position: "absolute",
    left: `${x * 100}%`,
    top: `${y * 100}%`,
    width: `${bb.width * 100}%`,
    height: `${bb.height * 100}%`,
    overflow: "hidden",
    margin: "0",
  };
}

// --- Drag ---

function startDrag(event: PointerEvent, el: ElementItem) {
  if (editState.value?.elementId === el.id) return;

  const bb = bboxByElement.value[el.id];
  if (!bb || !canvasRef.value) return;

  event.preventDefault();
  (event.currentTarget as Element).setPointerCapture(event.pointerId);

  const rect = canvasRef.value.getBoundingClientRect();

  dragState.value = {
    elementId: el.id,
    pointerId: event.pointerId,
    startFracX: (event.clientX - rect.left) / rect.width,
    startFracY: (event.clientY - rect.top) / rect.height,
    startElemX: bb.x,
    startElemY: bb.y,
    currentX: bb.x,
    currentY: bb.y,
    hasMoved: false,
  };
}

function onDrag(event: PointerEvent) {
  if (!dragState.value || !canvasRef.value) return;

  const rect = canvasRef.value.getBoundingClientRect();
  const fracX = (event.clientX - rect.left) / rect.width;
  const fracY = (event.clientY - rect.top) / rect.height;

  const dx = fracX - dragState.value.startFracX;
  const dy = fracY - dragState.value.startFracY;

  if (Math.abs(dx) > 0.005 || Math.abs(dy) > 0.005) {
    dragState.value.hasMoved = true;
  }

  const bb = bboxByElement.value[dragState.value.elementId];
  if (!bb) return;

  dragState.value.currentX = Math.max(0, Math.min(1 - bb.width, dragState.value.startElemX + dx));
  dragState.value.currentY = Math.max(0, Math.min(1 - bb.height, dragState.value.startElemY + dy));
}

function endDrag(event: PointerEvent) {
  if (!dragState.value || dragState.value.pointerId !== event.pointerId) return;

  const { elementId, currentX, currentY, hasMoved } = dragState.value;
  dragState.value = null;

  if (hasMoved) {
    emit("move-element", elementId, currentX, currentY);
  } else {
    emit("select-element", elementId);
  }
}

function cancelDrag() {
  dragState.value = null;
}

// --- Inline edit ---

function startEdit(event: MouseEvent, el: ElementItem) {
  if (el.element_type === "image") return;

  event.stopPropagation();
  const content = el.content ?? "";
  editState.value = { elementId: el.id, content, originalContent: content };

  nextTick(() => {
    const ta = document.getElementById(`edit-${el.id}`) as HTMLTextAreaElement | null;
    ta?.focus();
    ta?.select();
  });
}

function saveEdit(el: ElementItem) {
  if (!editState.value || editState.value.elementId !== el.id) return;

  const { elementId, content, originalContent } = editState.value;
  editState.value = null;

  if (content !== originalContent) {
    emit("update-content", elementId, content);
  }
}

function cancelEdit() {
  editState.value = null;
}
</script>

<style scoped>
.page-view {
  padding: 32px;
  overflow-y: auto;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  min-height: 0;
}

.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 60vh;
  width: 100%;
  color: var(--text-muted);
  font-size: 16px;
}

.page-content {
  width: 100%;
  max-width: 680px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.overflow-error {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: #fff3cd;
  border: 1px solid #ffc107;
  border-radius: var(--radius);
  color: #856404;
  font-size: 13px;
  font-weight: 500;
}

.overflow-icon {
  font-size: 15px;
}

.page-canvas {
  position: relative;
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  width: 100%;
  overflow: hidden;
  /* fallback height when no aspect-ratio from format */
  min-height: 400px;
}

.page-canvas:not([style*="aspect-ratio"]) {
  padding: 40px;
}

.page-canvas.has-overflow {
  border-color: #ffc107;
}

.page-element {
  border-radius: 4px;
}

/* When element has layout positioning, margin is zeroed via inline style */
.page-element:not([style*="position"]) {
  margin-bottom: 16px;
}

.page-element.selectable {
  cursor: grab;
  padding: 8px;
  border: 2px solid transparent;
  transition: border-color 0.15s;
  box-sizing: border-box;
  user-select: none;
}

.page-element.selectable:hover {
  border-color: var(--primary-light);
  background: rgba(74, 108, 247, 0.03);
}

.page-element.el-dragging {
  cursor: grabbing;
  border-color: var(--primary-light);
  box-shadow: 0 4px 16px rgba(74, 108, 247, 0.18);
  z-index: 10;
  opacity: 0.92;
}

.page-element.el-editing {
  cursor: default;
  border-color: var(--primary-light);
  background: rgba(74, 108, 247, 0.03);
}

.page-element.el-overflows {
  outline: 2px dashed #ffc107;
  outline-offset: 1px;
}

.el-title h2 {
  font-size: 24px;
  font-weight: 700;
  line-height: 1.3;
  margin: 0;
}

.el-text {
  font-size: 15px;
  line-height: 1.7;
  color: var(--text);
  overflow: hidden;
  width: 100%;
  height: 100%;
}

.el-edit-textarea {
  width: 100%;
  height: 100%;
  min-height: 60px;
  resize: none;
  border: none;
  outline: none;
  background: transparent;
  font: inherit;
  color: inherit;
  line-height: inherit;
  padding: 0;
  margin: 0;
  box-sizing: border-box;
}

.el-image-wrapper {
  width: 100%;
  height: 100%;
  overflow: hidden;
}

.el-image-wrapper img {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: cover;
}
</style>
