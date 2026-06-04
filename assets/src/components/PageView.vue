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

      <div class="page-canvas" :class="{ 'has-overflow': overflowingElements.length > 0 }" :style="canvasStyle">
        <div
          v-for="el in page.elements"
          :key="el.id"
          class="page-element"
          :class="['el-' + el.element_type, { selectable: true, 'el-overflows': isOverflowing(el.id) }]"
          :style="elementStyle(el)"
          @click="$emit('select-element', el.id)"
        >
          <div v-if="el.element_type === 'image' && el.latest_version?.asset_path" class="el-image-wrapper">
            <img :src="'/api/assets/' + el.latest_version.asset_path" alt="" />
          </div>
          <div v-else class="el-text">
            <template v-if="el.element_type === 'title'">
              <h2>{{ el.latest_version?.content || "" }}</h2>
            </template>
            <template v-else>
              {{ el.latest_version?.content || "" }}
            </template>
          </div>
        </div>
      </div>
    </div>
  </main>
</template>

<script setup lang="ts">
import { computed } from "vue";
import type { Page, ElementItem } from "../api";

const props = defineProps<{
  page: Page | null;
}>();

defineEmits<{
  "select-element": [elementId: string];
}>();

// Use the most recent layout (first in the array, sorted newest-first by the API)
const primaryLayout = computed(() => props.page?.layouts?.[0] ?? null);

const format = computed(() => primaryLayout.value?.format ?? null);

const hasLayout = computed(() => primaryLayout.value !== null);

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
  return {
    position: "absolute",
    left: `${bb.x * 100}%`,
    top: `${bb.y * 100}%`,
    width: `${bb.width * 100}%`,
    height: `${bb.height * 100}%`,
    overflow: "hidden",
    margin: "0",
  };
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
  cursor: pointer;
  padding: 8px;
  border: 2px solid transparent;
  transition: border-color 0.15s;
  box-sizing: border-box;
}

.page-element.selectable:hover {
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
