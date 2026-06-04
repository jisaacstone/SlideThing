<template>
  <div class="app">
    <OutlineSidebar
      ref="sidebarRef"
      :books="books"
      :pages="pages"
      :selectedPageId="selectedPageId"
      :bookTitle="currentBook?.title || ''"
      @back-to-books="backToBooks"
      @select-book="selectBook"
      @create-book="handleCreateBook"
      @select-page="selectPage"
      @create-page="handleCreatePage"
      @delete-page="handleDeletePage"
      @delete-book="handleDeleteBook"
    />

    <PageView
      :page="currentPage"
      @select-element="selectElement"
    />

    <PromptPanel
      :selectionLabel="selectionLabel"
      :targetType="targetType"
      :targetId="targetId"
      :bookId="currentBookId || ''"
      :prompts="prompts"
      :isRunning="isRunning"
      @close="closePanel"
      @submit="submitPrompt"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted } from "vue";
import type { Book, Page, PromptEntry, RunEvent } from "./api";
import {
  channel,
  fetchBooks,
  createBook,
  fetchBook,
  fetchPage,
  fetchPrompts,
  startRun,
  deleteBook,
  deletePage,
  createPage,
} from "./api";
import OutlineSidebar from "./components/OutlineSidebar.vue";
import PageView from "./components/PageView.vue";
import PromptPanel from "./components/PromptPanel.vue";

const books = ref<Book[]>([]);
const pages = ref<Page[]>([]);
const currentBookId = ref<string | null>(null);
const currentBook = ref<Book | null>(null);
const currentPage = ref<Page | null>(null);
const selectedPageId = ref<string | null>(null);
const selectedElementId = ref<string | null>(null);
const prompts = ref<PromptEntry[]>([]);
const isRunning = ref(false);

const targetType = computed(() => {
  if (selectedElementId.value) return "element";
  if (selectedPageId.value) return "page";
  return "";
});

const targetId = computed(() => {
  return selectedElementId.value || selectedPageId.value || "";
});

const selectionLabel = computed(() => {
  if (selectedElementId.value && currentPage.value) {
    const el = currentPage.value.elements.find((e) => e.id === selectedElementId.value);
    if (el) return `${el.element_type} element`;
    return "Element";
  }
  if (selectedPageId.value && currentPage.value) {
    return `Page ${currentPage.value.position}`;
  }
  return "";
});

const previousBookId = ref<string | null>(null);

watch(currentBookId, (_, oldVal) => {
  previousBookId.value = oldVal;
});

onMounted(() => {
  channel.connect();
  loadBooks();
});

async function loadBooks() {
  books.value = await fetchBooks();
}

async function backToBooks() {
  currentBookId.value = null;
  currentBook.value = null;
  currentPage.value = null;
  selectedPageId.value = null;
  selectedElementId.value = null;
  pages.value = [];
  prompts.value = [];
  await loadBooks();
}

async function selectBook(bookId: string) {
  channel.leave(`book:${previousBookId.value}`);
  currentBookId.value = bookId;
  currentPage.value = null;
  selectedPageId.value = null;
  selectedElementId.value = null;
  prompts.value = [];

  currentBook.value = await fetchBook(bookId);
  await loadPages(bookId);
}

async function loadPages(bookId: string) {
  channel.leave(`book:${bookId}`);
  channel.join(`book:${bookId}`, {
    page_event() {},
    book_event() {},
  });

  const book = await fetchBook(bookId);
  if (book?.pages) {
    const fullPages = await Promise.all(book.pages.map((p) => fetchPage(p.id)));
    pages.value = fullPages;
  }
}

async function selectPage(pageId: string) {
  selectedPageId.value = pageId;
  selectedElementId.value = null;

  const page = await fetchPage(pageId);
  currentPage.value = page;

  if (currentBookId.value) {
    await loadPrompts();
  }
}

function selectElement(elementId: string) {
  selectedElementId.value = elementId;
  if (currentBookId.value) {
    loadPrompts();
  }
}

function closePanel() {
  selectedPageId.value = null;
  selectedElementId.value = null;
  prompts.value = [];
}

async function handleCreateBook(title: string) {
  const trimmed = title.trim();
  if (!trimmed) return;
  const result = await createBook(trimmed);
  await loadBooks();
  await selectBook(result.book_id);
}

async function handleCreatePage() {
  if (!currentBookId.value) return;
  await createPage(currentBookId.value);
  await loadPages(currentBookId.value);
}

async function handleDeletePage(pageId: string) {
  if (!currentBookId.value || !confirm("Delete this page?")) return;
  await deletePage(pageId);
  if (selectedPageId.value === pageId) {
    selectedPageId.value = null;
    currentPage.value = null;
  }
  await loadPages(currentBookId.value);
}

async function handleDeleteBook() {
  if (!currentBookId.value || !confirm("Delete this book and all its pages?")) return;
  await deleteBook(currentBookId.value);
  await backToBooks();
}

async function loadPrompts() {
  if (!currentBookId.value) return;
  prompts.value = await fetchPrompts(currentBookId.value, targetId.value || undefined);
}

async function submitPrompt(text: string, ttype: string, tid: string) {
  if (isRunning.value || !text || !currentBookId.value) return;
  isRunning.value = true;

  try {
    const result = await startRun(text, currentBookId.value, ttype, tid);

    channel.join(`run:${result.run_id}`, {
      run_event(event: RunEvent) {
        if (event.event === "completed" || event.status === "done") {
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
          loadPrompts();
          if (currentBookId.value) loadPages(currentBookId.value);
          if (selectedPageId.value) selectPage(selectedPageId.value);
        }
        if (event.event === "failed" || event.status === "failed") {
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
        }
      },
      agent_event(_event: any) {},
    });
  } catch {
    isRunning.value = false;
  }
}
</script>

<style>
@import "../css/app.css";
</style>

<style scoped>
.app {
  display: grid;
  grid-template-columns: 260px 1fr auto;
  min-height: 100vh;
}
</style>