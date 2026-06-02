declare global {
  interface Window {
    Phoenix: any;
  }
}

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

export interface Element {
  id: string;
  page_id: string;
  element_type: string;
  position: number;
  locked: boolean;
  versions: ElementVersion[];
  created_at: string;
  updated_at: string;
}

export interface Layout {
  id: string;
  page_id: string;
  format_id: string;
  version: number;
  run_id: string | null;
  element_layouts: ElementLayoutItem[];
  created_at: string;
}

export interface ElementLayoutItem {
  element_id: string;
  bounding_box: { x: number; y: number; width: number; height: number };
  style?: Record<string, any>;
}

export interface Format {
  id: string;
  name: string;
  unit: string;
  width: number;
  height: number;
  dpi: number;
  bleed_mm: number | null;
  safe_margin_mm: number | null;
}

export interface RunEvent {
  type: string;
  status?: string;
  phase?: string;
  data?: any;
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
    this.socket = new window.Phoenix.Socket(WS_URL);
    this.socket.connect();
  }

  join(
    topic: string,
    handlers: Record<string, (payload: any) => void> = {}
  ) {
    const ch = this.socket.channel(topic, {});
    ch.onMessage = (_ev: string, payload: any) => {
      return payload;
    };

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

export async function fetchBook(bookId: string): Promise<Book> {
  const res = await fetch(`/api/books/${bookId}`);
  if (!res.ok) throw new Error(`book not found: ${bookId}`);
  return res.json();
}

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

export async function fetchPage(pageId: string): Promise<Page> {
  const res = await fetch(`/api/pages/${pageId}`);
  if (!res.ok) throw new Error(`page not found: ${pageId}`);
  return res.json();
}

export async function fetchElements(pageId: string): Promise<ElementItem[]> {
  const res = await fetch(`/api/pages/${pageId}/elements`);
  if (!res.ok) return [];
  return res.json();
}

export async function fetchLayout(pageId: string, formatId: string): Promise<Layout | null> {
  const res = await fetch(`/api/pages/${pageId}/layouts/${formatId}`);
  if (!res.ok) return null;
  return res.json();
}

export async function fetchLayouts(pageId: string): Promise<Layout[]> {
  const res = await fetch(`/api/pages/${pageId}/layouts`);
  if (!res.ok) return [];
  return res.json();
}

export async function startRun(
  prompt: string,
  bookId?: string
): Promise<{ run_id: string }> {
  const res = await fetch("/api/runs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ prompt, book_id: bookId }),
  });
  return res.json();
}

export async function getRunStatus(runId: string): Promise<RunStatus> {
  const res = await fetch(`/api/runs/${runId}`);
  return res.json();
}