<template>
  <aside class="sidebar">
    <div class="sidebar-header">
      <button v-if="bookTitle" class="btn-ghost back-btn" @click="$emit('back-to-books')">
        ← Books
      </button>
      <div v-else class="sidebar-header-title">
        <h2>Books</h2>
      </div>
      <button v-if="bookTitle" class="btn-ghost delete-book-btn" @click="$emit('delete-book')" title="Delete book">
        ✕
      </button>
    </div>

    <div v-if="!bookTitle" class="book-list-view">
      <div class="new-book-form">
        <input
          v-model="newBookTitle"
          placeholder="Book title..."
          @keyup.enter="$emit('create-book', newBookTitle)"
          ref="newBookInput"
        />
        <button class="btn-primary btn-sm" @click="$emit('create-book', newBookTitle)">Create</button>
      </div>
      <ul class="book-list">
        <li
          v-for="book in books"
          :key="book.id"
          @click="$emit('select-book', book.id)"
        >
          {{ book.title || "Untitled" }}
        </li>
      </ul>
    </div>

    <div v-else class="outline-view">
      <h3 class="outline-book-title">{{ bookTitle }}</h3>
      <span class="outline-page-count">{{ pages.length }} pages</span>

      <button class="btn-ghost new-page-btn" @click="$emit('create-page')">+ New Page</button>

      <ul class="outline-list">
        <li
          v-for="page in pages"
          :key="page.id"
          class="outline-item"
          :class="{ active: page.id === selectedPageId }"
          @click="$emit('select-page', page.id)"
        >
          <span class="outline-icon">#</span>
          <span class="outline-label">Page {{ page.position }}</span>
          <button class="btn-ghost delete-btn" @click.stop="$emit('delete-page', page.id)" title="Delete page">✕</button>
        </li>
      </ul>
    </div>
  </aside>
</template>

<script setup lang="ts">
import { ref, nextTick, watch, type PropType } from "vue";
import type { Book, Page } from "../api";

defineProps({
  books: { type: Array as PropType<Book[]>, default: () => [] },
  pages: { type: Array as PropType<Page[]>, default: () => [] },
  selectedPageId: { type: String as PropType<string | null>, default: null },
  bookTitle: { type: String, default: "" },
});

defineEmits<{
  "back-to-books": [];
  "select-book": [bookId: string];
  "create-book": [title: string];
  "select-page": [pageId: string];
  "create-page": [];
  "delete-page": [pageId: string];
  "delete-book": [];
}>();

const newBookTitle = ref("");
const newBookInput = ref<HTMLInputElement | null>(null);

watch(
  () => newBookTitle.value,
  () => nextTick(() => newBookInput.value?.focus())
);
</script>

<style scoped>
.sidebar {
  background: var(--sidebar-bg);
  color: var(--sidebar-text);
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

.sidebar-header {
  padding: 16px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.back-btn {
  background: none;
  border: none;
  color: var(--sidebar-text-muted);
  font-size: 14px;
  text-align: left;
  padding: 4px 0;
}

.back-btn:hover {
  color: var(--sidebar-text);
}

.delete-book-btn {
  background: none;
  border: none;
  color: var(--sidebar-text-muted);
  font-size: 14px;
  padding: 2px 6px;
  border-radius: 4px;
  cursor: pointer;
}

.delete-book-btn:hover {
  background: rgba(255, 80, 80, 0.2);
  color: #ff6666;
}

.sidebar-header-title {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.sidebar-header-title h2 {
  font-size: 16px;
  font-weight: 600;
}

.back-btn {
  background: none;
  border: none;
  color: var(--sidebar-text-muted);
  font-size: 14px;
  text-align: left;
  width: 100%;
  padding: 4px 0;
}

.back-btn:hover {
  color: var(--sidebar-text);
}

.book-list-view {
  flex: 1;
  overflow-y: auto;
  padding: 0 16px 16px;
}

.outline-view {
  flex: 1;
  overflow-y: auto;
  padding: 0 16px 16px;
}

.outline-book-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 2px;
}

.outline-page-count {
  font-size: 12px;
  color: var(--sidebar-text-muted);
}

.new-book-form {
  margin-bottom: 12px;
  display: flex;
  gap: 8px;
}

.new-book-form input {
  flex: 1;
  padding: 6px 8px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.1);
  color: var(--sidebar-text);
  font-size: 13px;
  outline: none;
}

.book-list {
  list-style: none;
}

.book-list li {
  padding: 8px 10px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
}

.book-list li:hover {
  background: rgba(255, 255, 255, 0.08);
}

.outline-list {
  list-style: none;
  margin-top: 12px;
}

.outline-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
}

.outline-item:hover {
  background: rgba(255, 255, 255, 0.08);
}

.outline-item.active {
  background: rgba(255, 255, 255, 0.15);
}

.outline-icon {
  font-size: 10px;
  color: var(--sidebar-text-muted);
}

.outline-label {
  flex: 1;
}

.delete-btn {
  background: none;
  border: none;
  color: var(--sidebar-text-muted);
  font-size: 11px;
  padding: 2px 4px;
  border-radius: 3px;
  cursor: pointer;
}

.delete-btn:hover {
  background: rgba(255, 80, 80, 0.2);
  color: #ff6666;
}

.new-page-btn {
  background: none;
  border: 1px dashed rgba(255, 255, 255, 0.2);
  color: var(--sidebar-text-muted);
  font-size: 13px;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  width: 100%;
  margin-top: 12px;
  transition: border-color 0.15s, color 0.15s;
}

.new-page-btn:hover {
  border-color: var(--primary);
  color: var(--primary);
}
</style>