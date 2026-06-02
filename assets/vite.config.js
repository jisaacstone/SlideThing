import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  root: ".",
  build: {
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  publicDir: "public",
  server: {
    proxy: {
      "/api": "http://localhost:4000",
      "/socket": {
        target: "ws://localhost:4000",
        ws: true,
      },
    },
  },
});