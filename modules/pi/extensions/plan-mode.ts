import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";

const ENTRY_TYPE = "plan-mode";
const PLAN_ALLOWED_TOOLS = new Set([
  "read",
  "grep",
  "find",
  "ls",
  "git_inspect",
  "ask_question",
  "project_tasks",
]);

interface PlanModeState {
  enabled: boolean;
  toolsBeforePlanMode?: string[];
}

function isMutatingProjectTask(input: Record<string, unknown>): boolean {
  const action = String(
    input.action ?? input.operation ?? input.command ?? "",
  ).toLowerCase();
  return /^(?:add|create|update|edit|delete|remove|clear|complete|uncomplete|start|stop|move|reorder|set|assign|claim|append|rename|archive|restore|mark)/.test(
    action,
  );
}

function updateStatus(ctx: ExtensionContext, enabled: boolean): void {
  if (!ctx.hasUI) return;
  ctx.ui.setStatus("plan-mode", enabled ? "󰏫 plan" : undefined);
}

export default function planMode(pi: ExtensionAPI): void {
  let enabled = false;
  let toolsBeforePlanMode: string[] | undefined;

  function persist(): void {
    pi.appendEntry(ENTRY_TYPE, { enabled, toolsBeforePlanMode });
  }

  function available(names: string[]): string[] {
    const known = new Set(pi.getAllTools().map((tool) => tool.name));
    return names.filter((name) => known.has(name));
  }

  function enable(): void {
    if (!toolsBeforePlanMode) toolsBeforePlanMode = [...pi.getActiveTools()];
    pi.setActiveTools(
      available(toolsBeforePlanMode).filter((name) =>
        PLAN_ALLOWED_TOOLS.has(name),
      ),
    );
  }

  function disable(): void {
    if (toolsBeforePlanMode) pi.setActiveTools(available(toolsBeforePlanMode));
    toolsBeforePlanMode = undefined;
  }

  function toggle(ctx: ExtensionContext): void {
    enabled = !enabled;
    if (enabled) enable();
    else disable();
    updateStatus(ctx, enabled);
    persist();
  }

  pi.registerCommand("plan-mode", {
    description: "Toggle persistent read-only plan mode",
    handler: async (_args, ctx) => toggle(ctx),
  });
  pi.registerShortcut(Key.ctrlShift("p"), {
    description: "Toggle plan mode",
    handler: async (ctx) => toggle(ctx),
  });

  pi.on("input", async (event, ctx) => {
    const command = event.text.trimStart();
    if (/^\/spec(?:\s|$)/.test(command) && !enabled) {
      enabled = true;
      enable();
      updateStatus(ctx, enabled);
      persist();
    } else if (/^\/solve(?:\s|$)/.test(command) && enabled) {
      enabled = false;
      disable();
      updateStatus(ctx, enabled);
      persist();
    }
  });

  pi.on("tool_call", async (event) => {
    if (!enabled) return;
    const input = (event.input ?? {}) as Record<string, unknown>;
    const tool = event.toolName.toLowerCase();
    if (!PLAN_ALLOWED_TOOLS.has(tool))
      return {
        block: true,
        reason: `Plan mode blocks tool ${event.toolName}; disable /plan-mode to restore normal tools.`,
      };
    if (tool === "project_tasks" && isMutatingProjectTask(input)) {
      return {
        block: true,
        reason: "Plan mode blocks mutating project_tasks actions.",
      };
    }
  });

  pi.on("before_agent_start", async (event) => {
    if (!enabled) return;
    return {
      systemPrompt: `${event.systemPrompt}\n\n## Plan mode\nYou are in persistent read-only plan mode. Explore the repository without changing files or running mutating commands. Use only read-only inspection/search tools. Produce a clear numbered implementation plan (1., 2., 3., ...). Do not execute the plan, make edits, or create a duplicate project task board.`,
    };
  });

  pi.on("session_start", async (_event, ctx) => {
    // Session replacement gets a clean local state; restore only from its entries.
    enabled = false;
    toolsBeforePlanMode = undefined;
    const entries = ctx.sessionManager.getEntries();
    const saved = [...entries]
      .reverse()
      .find(
        (entry) => entry.type === "custom" && entry.customType === ENTRY_TYPE,
      ) as { data?: PlanModeState } | undefined;
    if (saved?.data) {
      enabled = saved.data.enabled === true;
      toolsBeforePlanMode = saved.data.toolsBeforePlanMode
        ? [...saved.data.toolsBeforePlanMode]
        : undefined;
    }
    if (enabled) enable();
    updateStatus(ctx, enabled);
  });
}
