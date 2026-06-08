<template>
  <div class="markdown-content" v-html="sanitized" />
</template>

<script setup lang="ts">
import { computed } from "vue";
import { marked } from "marked";
import DOMPurify from "dompurify";

const props = defineProps<{ content: string }>();

const sanitized = computed(() =>
  DOMPurify.sanitize(marked.parse(props.content) as string)
);
</script>

<style scoped>
.markdown-content :deep(h1),
.markdown-content :deep(h2),
.markdown-content :deep(h3) {
  margin: 0 0 8px;
  font-weight: 700;
  line-height: 1.3;
}

.markdown-content :deep(p) {
  margin: 0 0 8px;
}

.markdown-content :deep(p:last-child) {
  margin-bottom: 0;
}

.markdown-content :deep(ul),
.markdown-content :deep(ol) {
  margin: 0 0 8px;
  padding-left: 1.4em;
}

.markdown-content :deep(li) {
  margin-bottom: 2px;
}

.markdown-content :deep(strong) {
  font-weight: 600;
}

.markdown-content :deep(em) {
  font-style: italic;
}
</style>
