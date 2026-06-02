<template>
  <div class="app">
    <aside class="sidebar">
      <div class="sidebar-header">
        <h2>Books</h2>
        <button class="btn btn-sm" @click="showNewBook = true">New</button>
      </div>
      <div v-if="showNewBook" class="new-book-form">
        <input
          v-model="newBookTitle"
          placeholder="Book title..."
          @keyup.enter="handleCreateBook"
          ref="newBookInput"
        />
        <button class="btn btn-sm" @click="handleCreateBook">Create</button>
      </div>
      <ul class="book-list">
        <li
          v-for="book in books"
          :key="book.id"
          :class="{ active: book.id === currentBookId }"
          @click="selectBook(book.id)"
        >
          {{ book.title || "Untitled" }}
        </li>
      </ul>
    </aside>

    <main class="main">
      <div v-if="!currentBookId" class="empty-state">
        <p>Select a book or create a new one.</p>
      </div>

      <div v-else class="book-view">
        <header class="book-header">
          <h1>{{ currentBook?.title || "Untitled" }}</h1>
          <span v-if="currentBook" class="page-count">{{ pages.length }} pages</span>
        </header>

        <div class="pages" ref="pagesContainer">
          <div
            v-for="page in pages"
            :key="page.id"
            class="page-card"
            @click="selectPage(page.id)"
          >
            <div class="page-preview">
              <div
                v-for="el in page.elements"
                :key="el.id"
                class="page-element"
                :class="'el-' + el.element_type"
              >
                <div v-if="el.element_type === 'image' && el.latest_version?.asset_path" class="el-image-wrapper">
                  <img :src="'/api/assets/' + el.latest_version.asset_path" alt="" />
                </div>
                <div v-else class="el-text">
                  {{ el.latest_version?.content || "" }}
                </div>
              </div>
            </div>
            <span class="page-label">Page {{ page.position }}</span>
          </div>
        </div>

        <div class="prompt-bar">
          <textarea
            v-model="prompt"
            placeholder="Describe what you want to create or change..."
            @keydown.enter.exact.prevent="submitPrompt"
            rows="2"
          ></textarea>
          <button
            class="btn btn-primary"
            :disabled="isRunning || !prompt.trim()"
            @click="submitPrompt"
          >
            {{ isRunning ? "Generating..." : "Generate" }}
          </button>
        </div>

        <div v-if="runStatus" class="run-status">
          <span class="status-badge" :class="'status-' + runStatus.status">
            {{ runStatus.status }}
          </span>
          <span v-if="runStatus.phase">Phase: {{ runStatus.phase }}</span>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, nextTick, watch, type Ref } from "vue";
import type { Book, Page } from "./api";
import channel, {
  fetchBooks,
  createBook,
  fetchBook,
  fetchPage,
} from "./api.js";

const books: Ref<Book[]> = ref([]);
const currentBookId: Ref<string | null> = ref(null);
const currentBook: Ref<Book | null> = ref(null);
const pages: Ref<Page[]> = ref([]);
const prompt = ref("");
const isRunning = ref(false);
const runStatus: Ref<RunStatusDisplay | null> = ref(null);
const showNewBook = ref(false);
const newBookTitle = ref("");
const newBookInput: Ref<HTMLInputElement | null> = ref(null);

interface RunStatusDisplay {
  status: string;
  type?: string;
  phase?: string;
  error?: string;
}

onMounted(async () => {
  channel.connect();
  await loadBooks();
});

watch(showNewBook, (val) => {
  if (val) nextTick(() => newBookInput.value?.focus());
});

async function loadBooks() {
  books.value = await fetchBooks();
}

async function selectBook(bookId: string) {
  currentBookId.value = bookId;
  currentBook.value = await fetchBook(bookId);

  channel.leave(`book:${bookId}`);

  channel.join(`book:${bookId}`, {
    onJoin() {
      channel.push(`book:${bookId}`, "get_pages", {}).receive("ok", (data: Page[]) => {
        pages.value = data;
      });
    },
  });

  const channelResult = await fetchBook(bookId);
  if (channelResult?.pages) {
    const fullPages = await Promise.all(
      channelResult.pages.map((p) => fetchPage(p.id))
    );
    pages.value = fullPages;
  }
}

async function selectPage(pageId: string) {
  // placeholder for future page detail view
}

async function handleCreateBook() {
  const title = newBookTitle.value.trim();
  if (!title) return;
  const book = await createBook(title);
  await loadBooks();
  await selectBook(book.book_id);
  showNewBook.value = false;
  newBookTitle.value = "";
}

async function submitPrompt() {
  if (isRunning.value || !prompt.value.trim()) return;
  isRunning.value = true;
  runStatus.value = { status: "starting" };

  try {
    const result = await startRun(prompt.value, currentBookId.value);
    prompt.value = "";

    channel.join(`run:${result.run_id}`, {
      run_event(event) {
        runStatus.value = event.data || event;
        if (event.type === "done" || event.status === "done") {
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
          selectBook(currentBookId.value);
        }
        if (event.type === "failed" || event.status === "failed") {
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
        }
      },
      agent_event(event) {
        // individual agent progress
      },
    });
  } catch (e) {
    isRunning.value = false;
    runStatus.value = { status: "error", error: e.message };
  }
}
</script>

<style>
:root {
  --bg: #f8f9fa;
  --sidebar-bg: #1a1a2e;
  --sidebar-text: #e0e0e0;
  --card-bg: #fff;
  --border: #dee2e6;
  --primary: #4a6cf7;
  --primary-hover: #3b5de7;
  --text: #212529;
  --text-muted: #6c757d;
  --radius: 8px;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
}

.app {
  display: grid;
  grid-template-columns: 260px 1fr;
  min-height: 100vh;
}

.sidebar {
  background: var(--sidebar-bg);
  color: var(--sidebar-text);
  padding: 16px;
  overflow-y: auto;
}

.sidebar-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.sidebar-header h2 {
  font-size: 16px;
  font-weight: 600;
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

.book-list li.active {
  background: rgba(255, 255, 255, 0.15);
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

.main {
  padding: 24px;
  overflow-y: auto;
}

.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 60vh;
  color: var(--text-muted);
  font-size: 16px;
}

.book-header {
  display: flex;
  align-items: baseline;
  gap: 12px;
  margin-bottom: 20px;
}

.book-header h1 {
  font-size: 22px;
  font-weight: 700;
}

.page-count {
  color: var(--text-muted);
  font-size: 14px;
}

.pages {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 16px;
  margin-bottom: 24px;
}

.page-card {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
  cursor: pointer;
  transition: box-shadow 0.15s;
}

.page-card:hover {
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}

.page-preview {
  aspect-ratio: 1;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  overflow: hidden;
}

.page-label {
  display: block;
  padding: 6px 12px;
  font-size: 12px;
  color: var(--text-muted);
  border-top: 1px solid var(--border);
}

.page-element {
  overflow: hidden;
}

.el-title {
  font-size: 15px;
  font-weight: 600;
  line-height: 1.3;
}

.el-text {
  font-size: 12px;
  line-height: 1.4;
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

.prompt-bar {
  display: flex;
  gap: 10px;
  position: sticky;
  bottom: 16px;
}

.prompt-bar textarea {
  flex: 1;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  font-size: 14px;
  font-family: inherit;
  resize: none;
  outline: none;
}

.prompt-bar textarea:focus {
  border-color: var(--primary);
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
}

.btn-sm {
  padding: 4px 10px;
  font-size: 13px;
}

.btn-primary {
  background: var(--primary);
  color: #fff;
}

.btn-primary:hover {
  background: var(--primary-hover);
}

.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.run-status {
  margin-top: 10px;
  font-size: 13px;
  color: var(--text-muted);
  display: flex;
  gap: 12px;
}

.status-badge {
  font-weight: 600;
  text-transform: capitalize;
}

.status-started,
.status-planning,
.status-executing {
  color: var(--primary);
}

.status-done,
.status-committed {
  color: #28a745;
}

.status-failed {
  color: #dc3545;
}
</style>