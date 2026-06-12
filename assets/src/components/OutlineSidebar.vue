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
          @keyup.enter="newBookPrompt ? null : submitCreateBook()"
          ref="newBookInput"
        />
        <textarea
          v-model="newBookPrompt"
          placeholder="Initial prompt (optional)..."
          class="prompt-input"
          rows="2"
        />
        <button class="btn-primary btn-sm" @click="submitCreateBook()">Create</button>
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
      <div class="outline-book-header">
        <h3 class="outline-book-title">{{ bookTitle }}</h3>
        <button class="btn-ghost book-prompt-btn" @click="$emit('book-prompt')" title="Book-level prompt">✏</button>
      </div>
      <span class="outline-page-count">{{ pages.length }} pages</span>

      <div class="outline-actions">
        <button class="btn-ghost new-page-btn" @click="showAddPageDialog = true">+ New Page</button>
        <button class="btn-ghost download-btn" @click="$emit('download-pdf')" title="Download as PDF">⬇ PDF</button>
      </div>

      <!-- Add Page Dialog -->
      <div v-if="showAddPageDialog" class="dialog-overlay" @click.self="showAddPageDialog = false">
        <div class="dialog">
          <h4 class="dialog-title">Add Page</h4>
          <input
            v-model="newPageTitle"
            placeholder="Page title (optional)..."
            class="dialog-input"
            ref="newPageInput"
          />
          <textarea
            v-model="newPagePrompt"
            placeholder="Initial prompt (optional)..."
            class="dialog-textarea"
            rows="3"
          />
          <div class="dialog-actions">
            <button class="btn-ghost btn-sm" @click="cancelAddPage()">Cancel</button>
            <button class="btn-primary btn-sm" @click="submitAddPage()">Add Page</button>
          </div>
        </div>
      </div>

      <ul class="outline-list">
        <li
          v-for="page in pages"
          :key="page.id"
          class="outline-item"
          :class="{ active: page.id === selectedPageId }"
          @click="$emit('select-page', page.id)"
        >
          <span class="outline-icon">#</span>
          <span class="outline-label">{{ (page.metadata as any)?.title || `Page ${page.position}` }}</span>
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

const emit = defineEmits<{
  "back-to-books": [];
  "select-book": [bookId: string];
  "create-book": [title: string, prompt: string];
  "select-page": [pageId: string];
  "create-page": [];
  "add-page": [title: string, prompt: string];
  "delete-page": [pageId: string];
  "delete-book": [];
  "book-prompt": [];
  "download-pdf": [];
}>();

const newBookTitle = ref("");
const newBookPrompt = ref("");
const newBookInput = ref<HTMLInputElement | null>(null);
const showAddPageDialog = ref(false);
const newPageTitle = ref("");
const newPagePrompt = ref("");
const newPageInput = ref<HTMLInputElement | null>(null);

watch(showAddPageDialog, (val) => {
  if (val) nextTick(() => newPageInput.value?.focus());
});

function submitCreateBook() {
  if (!newBookTitle.value.trim()) return;
  emit("create-book", newBookTitle.value, newBookPrompt.value);
  newBookTitle.value = "";
  newBookPrompt.value = "";
}

function submitAddPage() {
  emit("add-page", newPageTitle.value, newPagePrompt.value);
  cancelAddPage();
}

function cancelAddPage() {
  showAddPageDialog.value = false;
  newPageTitle.value = "";
  newPagePrompt.value = "";
}

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

.outline-book-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 2px;
}

.outline-book-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 0;
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.book-prompt-btn {
  background: none;
  border: none;
  color: var(--sidebar-text-muted);
  font-size: 14px;
  padding: 2px 4px;
  flex-shrink: 0;
  opacity: 0.6;
}

.book-prompt-btn:hover {
  color: var(--sidebar-text);
  opacity: 1;
}

.outline-page-count {
  font-size: 12px;
  color: var(--sidebar-text-muted);
}

.new-book-form {
  margin-bottom: 12px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.new-book-form input,
.new-book-form .prompt-input {
  width: 100%;
  padding: 6px 8px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.1);
  color: var(--sidebar-text);
  font-size: 13px;
  outline: none;
  box-sizing: border-box;
}

.new-book-form .prompt-input {
  resize: none;
  font-family: inherit;
}

.dialog-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.dialog {
  background: var(--sidebar-bg);
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 8px;
  padding: 20px;
  width: 320px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.dialog-title {
  font-size: 15px;
  font-weight: 600;
  margin: 0;
}

.dialog-input,
.dialog-textarea {
  width: 100%;
  padding: 7px 10px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.1);
  color: var(--sidebar-text);
  font-size: 13px;
  outline: none;
  box-sizing: border-box;
  font-family: inherit;
}

.dialog-textarea {
  resize: none;
}

.dialog-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 4px;
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

.outline-actions {
  display: flex;
  gap: 6px;
  margin-top: 12px;
}

.new-page-btn {
  background: none;
  border: 1px dashed rgba(255, 255, 255, 0.2);
  color: var(--sidebar-text-muted);
  font-size: 13px;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  flex: 1;
  transition: border-color 0.15s, color 0.15s;
}

.new-page-btn:hover {
  border-color: var(--primary);
  color: var(--primary);
}

.download-btn {
  background: none;
  border: 1px solid rgba(255, 255, 255, 0.15);
  color: var(--sidebar-text-muted);
  font-size: 13px;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  white-space: nowrap;
  transition: border-color 0.15s, color 0.15s;
}

.download-btn:hover {
  border-color: var(--primary);
  color: var(--primary);
}
</style>