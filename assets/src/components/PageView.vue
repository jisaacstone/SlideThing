<template>
  <main class="page-view">
    <div v-if="!page" class="empty-state">
      <p>Select a page from the outline.</p>
    </div>

    <div v-else class="page-content">
      <div class="page-preview">
        <div
          v-for="el in page.elements"
          :key="el.id"
          class="page-element"
          :class="['el-' + el.element_type, { selectable: true }]"
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
import type { Page } from "../api";

defineProps<{
  page: Page | null;
}>();

defineEmits<{
  "select-element": [elementId: string];
}>();
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
}

.page-preview {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 40px;
  min-height: 600px;
}

.page-element {
  margin-bottom: 16px;
  border-radius: 4px;
}

.page-element.selectable {
  cursor: pointer;
  padding: 8px;
  margin: -8px;
  margin-bottom: 8px;
  border: 2px solid transparent;
  transition: border-color 0.15s;
}

.page-element.selectable:hover {
  border-color: var(--primary-light);
  background: rgba(74, 108, 247, 0.03);
}

.el-title h2 {
  font-size: 24px;
  font-weight: 700;
  line-height: 1.3;
}

.el-text {
  font-size: 15px;
  line-height: 1.7;
  color: var(--text);
}

.el-image-wrapper {
  width: 100%;
  border-radius: 4px;
  overflow: hidden;
}

.el-image-wrapper img {
  width: 100%;
  display: block;
}
</style>