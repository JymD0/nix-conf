import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

const EXIT_HINT_WINDOW_MS = 750;

/** Claude-like interrupt and exit behavior for the interactive editor. */
export default function claudeControls(pi: ExtensionAPI): void {
  let latestSubmittedPrompt: string | undefined;
  let lastEmptyInterruptAt = 0;
  let unsubscribe: (() => void) | undefined;
  let restoreTimer: ReturnType<typeof setTimeout> | undefined;

  pi.on("input", async (event) => {
    if (event.source === "interactive") latestSubmittedPrompt = event.text;
  });

  pi.on("session_start", async (_event, ctx) => {
    latestSubmittedPrompt = undefined;
    if (ctx.mode !== "tui") return;
    lastEmptyInterruptAt = 0;
    unsubscribe?.();
    unsubscribe = ctx.ui.onTerminalInput((data) => {
      if (!matchesKey(data, "ctrl+c")) return;

      const editorText = ctx.ui.getEditorText();
      if (!ctx.isIdle()) {
        lastEmptyInterruptAt = 0;
        const prompt = latestSubmittedPrompt;
        if (restoreTimer) clearTimeout(restoreTimer);
        restoreTimer = setTimeout(() => {
          restoreTimer = undefined;
          try {
            // Pi's native Escape path restores queued messages first. Only
            // restore the submitted prompt when that path left the editor empty.
            if (!ctx.ui.getEditorText() && prompt) ctx.ui.setEditorText(prompt);
          } catch {
            // Session replacement can invalidate the context before this tick.
          }
        }, 0);
        // Route through Pi's native interrupt handler so it also clears and
        // restores queued steering/follow-up messages before aborting.
        return { data: "\x1b" };
      }

      if (editorText) {
        ctx.ui.setEditorText("");
        lastEmptyInterruptAt = 0;
        return { consume: true };
      }

      const now = Date.now();
      if (now - lastEmptyInterruptAt <= EXIT_HINT_WINDOW_MS) {
        lastEmptyInterruptAt = 0;
        ctx.shutdown();
        return { consume: true };
      }

      lastEmptyInterruptAt = now;
      ctx.ui.notify("Press Ctrl+C again to exit", "info");
      // Pi reports user-invoked `!` Bash as agent-idle. Forward the first
      // empty-editor Ctrl+C as Escape so its native Bash cancellation still works.
      return { data: "\x1b" };
    });
  });

  pi.on("session_shutdown", async () => {
    unsubscribe?.();
    unsubscribe = undefined;
    if (restoreTimer) clearTimeout(restoreTimer);
    restoreTimer = undefined;
  });
}
