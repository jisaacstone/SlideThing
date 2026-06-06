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
      @add-page="handleAddPage"
      @delete-page="handleDeletePage"
      @delete-book="handleDeleteBook"
      @book-prompt="openBookPrompt"
    />

    <PageView
      :page="currentPage"
      @select-element="selectElement"
      @move-element="handleMoveElement"
      @update-content="handleUpdateContent"
    />

    <PromptPanel
      :selectionLabel="selectionLabel"
      :targetType="targetType"
      :targetId="targetId"
      :bookId="currentBookId || ''"
      :prompts="prompts"
      :isRunning="isRunning"
      :liveLog="liveLog"
      :runFinalStatus="runFinalStatus"
      :runFailReason="runFailReason"
      :selectedElement="selectedElement"
      @close="closePanel"
      @submit="submitPrompt"
      @delete="handleDeleteElement"
      @updateContent="handleUpdateContent"
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
  moveElement,
  updateElementContent,
  deleteElement,
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
const bookLevelOpen = ref(false);
const isRunning = ref(false);
const liveLog = ref<string[]>([]);
const runFinalStatus = ref<"idle" | "done" | "failed">("idle");
const runFailReason = ref("");

const targetType = computed(() => {
  if (selectedElementId.value) return "element";
  if (selectedPageId.value) return "page";
  if (bookLevelOpen.value) return "book";
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
  if (bookLevelOpen.value && currentBook.value) {
    return currentBook.value.title || "Book";
  }
  return "";
});

const selectedElement = computed(() => {
  if (selectedElementId.value && currentPage.value) {
    return currentPage.value.elements.find((e) => e.id === selectedElementId.value) || null;
  }
  return null;
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
  bookLevelOpen.value = false;

  const page = await fetchPage(pageId);
  currentPage.value = page;

  if (currentBookId.value) {
    await loadPrompts();
  }
}

function selectElement(elementId: string) {
  selectedElementId.value = elementId;
  bookLevelOpen.value = false;
  if (currentBookId.value) {
    loadPrompts();
  }
}

function closePanel() {
  selectedPageId.value = null;
  selectedElementId.value = null;
  bookLevelOpen.value = false;
  prompts.value = [];
}

async function openBookPrompt() {
  selectedPageId.value = null;
  selectedElementId.value = null;
  bookLevelOpen.value = true;
  if (currentBookId.value) {
    prompts.value = await fetchPrompts(currentBookId.value);
  }
}

async function handleCreateBook(title: string, prompt?: string) {
  const trimmed = title.trim();
  if (!trimmed) return;
  const result = await createBook(trimmed);
  await loadBooks();
  await selectBook(result.book_id);
  if (prompt?.trim()) {
    bookLevelOpen.value = true;
    prompts.value = [];
    await submitPrompt(prompt.trim(), "", "");
  }
}

async function handleCreatePage() {
  if (!currentBookId.value) return;
  await createPage(currentBookId.value);
  await loadPages(currentBookId.value);
}

async function handleAddPage(title: string, prompt: string) {
  if (!currentBookId.value) return;
  const page = await createPage(currentBookId.value, title.trim() || undefined);
  await loadPages(currentBookId.value);
  await selectPage(page.id);
  if (prompt.trim()) {
    await submitPrompt(prompt.trim(), "page", page.id);
  }
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

async function handleUpdateContent(elementId: string, content: string) {
  await updateElementContent(elementId, content);
  if (selectedPageId.value) selectPage(selectedPageId.value);
}

async function handleMoveElement(elementId: string, x: number, y: number) {
  if (!currentPage.value) return;
  const layout = currentPage.value.layouts[0];
  if (!layout) return;
  await moveElement(currentPage.value.id, layout.format_id, elementId, x, y);
  if (selectedPageId.value) selectPage(selectedPageId.value);
}

async function handleDeleteElement(elementId: string) {
  if (!confirm("Delete this element?")) return;
  await deleteElement(elementId);
  selectedElementId.value = null;
  prompts.value = [];
  if (selectedPageId.value) selectPage(selectedPageId.value);
}

function formatRunEvent(e: RunEvent): string | null {
  switch (e.event) {
    case "started": return "▶ Run started";
    case "planning_complete": return `📋 Plan: ${e.data?.phase_count ?? "?"} phases`;
    case "phase_started": return `⚙ Phase: ${e.data?.phase ?? JSON.stringify(e.data)}`;
    case "phase_completed": return `✓ Done: ${e.data?.phase ?? JSON.stringify(e.data)}`;
    case "completed": return `✓ Completed in ${e.data?.duration_ms ?? "?"}ms`;
    case "failed": return `✗ Failed: ${e.data?.reason ?? "unknown"}`;
    default: return null;
  }
}

function formatAgentEvent(e: any): string | null {
  switch (e.event) {
    case "llm_call_started": return `  ${e.agent_type} → thinking (iter ${e.data?.iteration ?? "?"})`;
    case "tools_executed": return `  ${e.agent_type} → ran ${e.data?.tool_count ?? "?"} tool(s)`;
    case "completed": return `  ${e.agent_type} done`;
    case "failed": return `  ${e.agent_type} failed: ${e.data?.reason ?? ""}`;
    default: return null;
  }
}

async function submitPrompt(text: string, ttype: string, tid: string) {
  if (isRunning.value || !text || !currentBookId.value) return;
  isRunning.value = true;
  liveLog.value = [];
  runFinalStatus.value = "idle";
  runFailReason.value = "";

  try {
    const result = await startRun(text, currentBookId.value, ttype, tid);

    channel.join(`run:${result.run_id}`, {
      run_event(event: RunEvent) {
        const msg = formatRunEvent(event);
        if (msg) liveLog.value.push(msg);

        if (event.event === "completed" || event.status === "done") {
          runFinalStatus.value = "done";
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
          loadPrompts();
          if (currentBookId.value) loadPages(currentBookId.value);
          if (selectedPageId.value) selectPage(selectedPageId.value);
        }
        if (event.event === "failed" || event.status === "failed") {
          runFinalStatus.value = "failed";
          runFailReason.value = event.data?.reason ?? "unknown error";
          isRunning.value = false;
          channel.leave(`run:${result.run_id}`);
          loadPrompts();
        }
      },
      agent_event(event: any) {
        const msg = formatAgentEvent(event);
        if (msg) liveLog.value.push(msg);
      },
    });
  } catch {
    isRunning.value = false;
    runFinalStatus.value = "failed";
    runFailReason.value = "Failed to start run";
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