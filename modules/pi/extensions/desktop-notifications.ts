import { readFile } from "node:fs/promises";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const CHILD_SESSION_NAME = /^[^#\s]+#[a-z0-9]{8}$/i;
const DEFAULT_AGENT_EXCLUDES = new Set(["default-agent"]);
const DEDUPE_MS = 1500;

type BusUnsubscribe = () => void;

async function parentPid(pid: number): Promise<number | undefined> {
  try {
    const stat = await readFile(`/proc/${pid}/stat`, "utf8");
    const end = stat.lastIndexOf(")");
    if (end < 0) return undefined;
    const fields = stat
      .slice(end + 2)
      .trim()
      .split(/\s+/);
    const ppid = Number(fields[1]);
    return Number.isInteger(ppid) && ppid >= 0 ? ppid : undefined;
  } catch {
    return undefined;
  }
}

async function terminalIsUnfocused(pi: ExtensionAPI): Promise<boolean> {
  try {
    const result = await pi.exec("hyprctl", ["activewindow", "-j"], {
      timeout: 1000,
    });
    if (result.code !== 0) return false;
    const active = JSON.parse(result.stdout) as {
      pid?: number;
      class?: string;
    };
    const activePid = Number(active.pid);
    if (!Number.isInteger(activePid) || activePid <= 0) return false;
    if (
      process.env.TMUX &&
      /(?:kitty|foot|alacritty|wezterm|ghostty|terminal|konsole)/i.test(
        active.class ?? "",
      )
    ) {
      // A tmux pane is parented by the tmux server rather than the focused
      // terminal process, so ancestry cannot prove focus in this case.
      return false;
    }

    const seen = new Set<number>();
    let pid = process.pid;
    while (pid > 1 && !seen.has(pid)) {
      if (pid === activePid) return false;
      seen.add(pid);
      const next = await parentPid(pid);
      if (next === undefined) return false;
      if (next === 0) break;
      pid = next;
    }
  } catch {
    // Missing Hyprland, an inaccessible /proc, or malformed output is
    // treated as focused so failures never spam the desktop.
    return false;
  }
  return true;
}

function payloadId(data: unknown): string {
  if (!data || typeof data !== "object") return "";
  const value = data as Record<string, unknown>;
  for (const key of ["id", "taskId", "processId", "runId", "sessionId"]) {
    if (typeof value[key] === "string" || typeof value[key] === "number")
      return String(value[key]);
  }
  return "";
}

export default function desktopNotifications(pi: ExtensionAPI): void {
  let currentCtx: ExtensionContext | undefined;
  let sessionToken = 0;
  let childSession = false;
  let unsubscribers: BusUnsubscribe[] = [];
  let suppressNextSettled = false;
  const recent = new Map<string, number>();

  async function notify(
    channel: string,
    title: string,
    body: string,
    token: number,
    key: string,
  ): Promise<void> {
    const now = Date.now();
    const previous = recent.get(key);
    if (previous !== undefined && now - previous < DEDUPE_MS) return;
    recent.set(key, now);
    for (const [entry, timestamp] of recent)
      if (now - timestamp >= DEDUPE_MS) recent.delete(entry);
    if (token !== sessionToken || !currentCtx || childSession) return;
    if (channel === "agent_settled" && suppressNextSettled) {
      suppressNextSettled = false;
      return;
    }
    if (!(await terminalIsUnfocused(pi))) return;
    if (token !== sessionToken || !currentCtx) return;
    try {
      const result = await pi.exec(
        "notify-send",
        ["--app-name", "Pi", title, body],
        { timeout: 2000 },
      );
      if (result.code === 0 && channel !== "agent_settled")
        suppressNextSettled = true;
    } catch {
      // Reload or session replacement may invalidate the API after the final token check.
    }
  }

  function busNotification(
    channel: string,
    title: string,
    body: string,
    data: unknown,
  ): void {
    const id = payloadId(data);
    void notify(
      channel,
      title,
      body,
      sessionToken,
      `${channel}:${id || "close"}`,
    );
  }

  pi.on("session_start", async (_event, ctx) => {
    sessionToken += 1;
    recent.clear();
    suppressNextSettled = false;
    currentCtx = ctx.mode === "tui" ? ctx : undefined;
    const name =
      ctx.sessionManager.getSessionName() ?? pi.getSessionName() ?? "";
    childSession =
      ctx.mode !== "tui" ||
      CHILD_SESSION_NAME.test(name) ||
      DEFAULT_AGENT_EXCLUDES.has(name);
    for (const unsubscribe of unsubscribers) unsubscribe();
    unsubscribers = currentCtx
      ? [
          pi.events.on("subagents:completed", (data) =>
            busNotification(
              "subagents:completed",
              "Pi",
              "Subagent completed",
              data,
            ),
          ),
          pi.events.on("subagents:failed", (data) =>
            busNotification("subagents:failed", "Pi", "Subagent failed", data),
          ),
          pi.events.on("process:completed", (data) =>
            busNotification(
              "process:completed",
              "Pi",
              "Process completed",
              data,
            ),
          ),
        ]
      : [];
  });

  pi.on("agent_settled", async () => {
    if (childSession) return;
    await notify(
      "agent_settled",
      "Pi",
      "Ready for input",
      sessionToken,
      "agent_settled",
    );
  });

  pi.on("session_shutdown", async () => {
    sessionToken += 1;
    currentCtx = undefined;
    childSession = false;
    for (const unsubscribe of unsubscribers) unsubscribe();
    unsubscribers = [];
  });
}
