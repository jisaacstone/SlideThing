/// <reference types="vite/client" />

declare module "phoenix" {
  export class Socket {
    constructor(endpoint: string, opts?: Record<string, any>);
    connect(params?: Record<string, any>): void;
    disconnect(callback?: () => void, code?: number, reason?: string): void;
    channel(topic: string, params?: Record<string, any>): Channel;
  }

  export class Channel {
    join(timeout?: number): Push;
    leave(timeout?: number): Push;
    on(event: string, callback: (payload: any) => void): number;
    off(event: string, ref?: number): void;
    push(event: string, payload?: any, timeout?: number): Push;
    onClose(callback: (payload: any) => void): number;
    onError(callback: (reason: any) => void): number;
    onMessage(callback: (event: string, payload: any) => void): number;
    trigger(event: string, payload?: any): number;
  }

  export class Push {
    receive(status: string, callback: (response: any) => void): this;
  }
}

declare module "*.vue" {
  import type { DefineComponent } from "vue";
  const component: DefineComponent<{}, {}, any>;
  export default component;
}
