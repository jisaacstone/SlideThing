import { Socket } from "phoenix";

export interface Book {
  id: string;
  title: string;
  metadata: Record<string, any>;
  pages?: PageRef[];
  created_at: string;
  updated_at: string;
}

export interface PageRef {
  id: string;
  position: number;
  metadata: Record<string, any>;
}

export interface Page extends PageRef {
  book_id: string;
  elements: ElementItem[];
  layouts: Layout[];
  created_at: string;
  updated_at: string;
}

export interface ElementItem {
  id: string;
  element_type: "title" | "text" | "image" | "caption";
  position: number;
  locked: boolean;
  latest_version?: ElementVersion;
}

export interface ElementVersion {
  version: number;
  content: string | null;
  asset_path: string | null;
  prompt: string | null;
}

export interface Format {
  name: string;
  unit: string;
  width: number;
  height: number;
  dpi: number;
  safe_margin_mm: number;
  bleed_mm: number;
}

export interface Layout {
  id: string;
  page_id: string;
  format_id: string;
  version: number;
  run_id: string | null;
  element_layouts: ElementLayoutItem[];
  created_at: string;
  format?: Format;
}

export interface ElementLayoutItem {
  element_id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  style?: Record<string, any>;
}

export interface PromptEntry {
  id: string;
  run_id: string;
  agent_type: string;
  user_prompt: string;
  result_summary: string | null;
  targets: PromptTarget[];
  created_at: string;
}

export interface PromptTarget {
  target_type: string;
  target_id: string;
}

export interface RunEvent {
  event: string;
  status: string;
  phase: string | null;
  data: any;
  run_id: string;
  timestamp: string;
}

export interface RunStatus {
  run_id: string;
  status: string;
  phase: string;
  prompt: string;
  book_id: string;
}

const WS_URL = `ws://${location.host}/socket`;

class Channel {
  private socket: any = null;
  private channels: Record<string, any> = {};

  connect() {
    this.socket = new Socket(WS_URL);
    this.socket.connect();
  }

  join(topic: string, handlers: Record<string, (payload: any) => void> = {}) {
    const ch = this.socket.channel(topic, {});
    ch.onMessage = (_ev: string, payload: any) => payload;

    ch.on("run_event", (payload: any) => handlers.run_event?.(payload));
    ch.on("agent_event", (payload: any) => handlers.agent_event?.(payload));
    ch.on("page_event", (payload: any) => handlers.page_event?.(payload));
    ch.on("book_event", (payload: any) => handlers.book_event?.(payload));

    ch.join()
      .receive("ok", (resp: any) => handlers.onJoin?.(resp))
      .receive("error", (resp: any) => handlers.onError?.(resp));

    this.channels[topic] = ch;
    return ch;
  }

  leave(topic: string) {
    if (this.channels[topic]) {
      this.channels[topic].leave();
      delete this.channels[topic];
    }
  }

  push(topic: string, event: string, payload: any = {}) {
    return this.channels[topic]?.push(event, payload);
  }

  disconnect() {
    this.socket?.disconnect();
  }
}

export const channel = new Channel();

export async function fetchBooks(): Promise<Book[]> {
  const res = await fetch("/api/books");
  return res.json();
}

export async function createBook(title: string): Promise<{ book_id: string; title: string }> {
  const res = await fetch("/api/books", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  return res.json();
}

export async function fetchBook(bookId: string): Promise<Book> {
  const res = await fetch(`/api/books/${bookId}`);
  if (!res.ok) throw new Error(`book not found: ${bookId}`);
  return res.json();
}

export async function fetchPage(pageId: string): Promise<Page> {
  const res = await fetch(`/api/pages/${pageId}`);
  if (!res.ok) throw new Error(`page not found: ${pageId}`);
  return res.json();
}

export async function fetchPrompts(bookId: string, targetId?: string): Promise<PromptEntry[]> {
  const params = targetId ? `?target_id=${encodeURIComponent(targetId)}` : "";
  const res = await fetch(`/api/books/${bookId}/prompts${params}`);
  if (!res.ok) return [];
  return res.json();
}

export async function startRun(
  prompt: string,
  bookId: string,
  targetType?: string,
  targetId?: string
): Promise<{ run_id: string }> {
  const body: Record<string, any> = { prompt, book_id: bookId };
  if (targetType) body.target_type = targetType;
  if (targetId) body.target_id = targetId;

  const res = await fetch("/api/runs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

export async function deleteBook(bookId: string): Promise<void> {
  const res = await fetch(`/api/books/${bookId}`, { method: "DELETE" });
  if (!res.ok) throw new Error("delete book failed");
}

export async function deletePage(pageId: string): Promise<void> {
  const res = await fetch(`/api/pages/${pageId}`, { method: "DELETE" });
  if (!res.ok) throw new Error("delete page failed");
}

export async function createPage(bookId: string): Promise<{ id: string; position: number }> {
  const res = await fetch(`/api/books/${bookId}/pages`, { method: "POST" });
  if (!res.ok) throw new Error("create page failed");
  return res.json();
}