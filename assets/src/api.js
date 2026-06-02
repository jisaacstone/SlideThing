const WS_URL = `ws://${location.host}/socket`;

class Channel {
  constructor() {
    this.socket = null;
    this.channels = {};
  }

  connect() {
    this.socket = new window.Phoenix.Socket(WS_URL);
    this.socket.connect();
  }

  join(topic, handlers = {}) {
    const channel = this.socket.channel(topic, {});
    channel.onMessage = (ev, payload) => {
      if (handlers[ev]) handlers[ev](payload);
    };

    channel
      .join()
      .receive("ok", (resp) => {
        if (handlers.onJoin) handlers.onJoin(resp);
      })
      .receive("error", (resp) => {
        if (handlers.onError) handlers.onError(resp);
      });

    this.channels[topic] = channel;
    return channel;
  }

  leave(topic) {
    if (this.channels[topic]) {
      this.channels[topic].leave();
      delete this.channels[topic];
    }
  }

  push(topic, event, payload) {
    return this.channels[topic]?.push(event, payload);
  }

  disconnect() {
    this.socket?.disconnect();
  }
}

const channel = new Channel();

export async function fetchBook(bookId) {
  const res = await fetch(`/api/books/${bookId}`);
  if (!res.ok) throw new Error(`book not found: ${bookId}`);
  return res.json();
}

export async function fetchBooks() {
  const res = await fetch("/api/books");
  return res.json();
}

export async function createBook(title) {
  const res = await fetch("/api/books", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  return res.json();
}

export async function fetchPage(pageId) {
  const res = await fetch(`/api/pages/${pageId}`);
  if (!res.ok) throw new Error(`page not found: ${pageId}`);
  return res.json();
}

export async function fetchElements(pageId) {
  const res = await fetch(`/api/pages/${pageId}/elements`);
  if (!res.ok) return [];
  return res.json();
}

export async function fetchLayout(pageId, formatId) {
  const res = await fetch(`/api/pages/${pageId}/layouts/${formatId}`);
  if (!res.ok) return null;
  return res.json();
}

export async function fetchLayouts(pageId) {
  const res = await fetch(`/api/pages/${pageId}/layouts`);
  if (!res.ok) return [];
  return res.json();
}

export async function startRun(prompt, bookId) {
  const res = await fetch("/api/runs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ prompt, book_id: bookId }),
  });
  return res.json();
}

export async function getRunStatus(runId) {
  const res = await fetch(`/api/runs/${runId}`);
  return res.json();
}

export { channel };
export default channel;