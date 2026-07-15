import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import { StringEnum } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
  Theme,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type, type Static } from "typebox";

const ProcessParams = Type.Object({
  action: StringEnum(
    ["start", "list", "status", "logs", "wait", "stop"] as const,
    {
      description: "Process operation to perform",
    },
  ),
  id: Type.Optional(
    Type.String({ description: "Managed process id or pi-bg unit name" }),
  ),
  cwd: Type.Optional(Type.String({ description: "Working directory (start)" })),
  command: Type.Optional(
    Type.String({ description: "Command to run (start)" }),
  ),
  description: Type.Optional(
    Type.String({
      description: "Human-readable description (start)",
      maxLength: 200,
    }),
  ),
  timeoutMs: Type.Optional(
    Type.Integer({
      description: "Wait timeout in milliseconds",
      minimum: 1,
      maximum: 300000,
    }),
  ),
  lines: Type.Optional(
    Type.Integer({
      description: "Maximum log lines",
      minimum: 1,
      maximum: 1000,
    }),
  ),
  maxBytes: Type.Optional(
    Type.Integer({
      description: "Maximum log bytes",
      minimum: 1,
      maximum: 50_000,
    }),
  ),
});

type ProcessParams = Static<typeof ProcessParams>;
type ProcessState = "running" | "completed" | "failed" | "stopped";

interface ProcessMetadata {
  id: string;
  unit: string;
  sessionId: string;
  cwd: string;
  command: string;
  description?: string;
  createdAt: string;
  startedAt: string;
  updatedAt: string;
  completedAt?: string;
  state: ProcessState;
  exitCode?: number;
  notification: { sent: boolean; sentAt?: string };
}

interface ProcessDetails {
  action: ProcessParams["action"];
  processes?: ProcessMetadata[];
  process?: ProcessMetadata;
  logs?: string;
  timedOut?: boolean;
  error?: string;
}

const UNIT_PREFIX = "pi-bg-";
const UNIT_RE = /^pi-bg-[a-z0-9-]+$/;
const ID_RE = /^[a-z0-9-]+$/;
const POLL_MS = 2000;
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const DEFAULT_WAIT_MS = 30000;
const MAX_COMMAND_LENGTH = 10000;

function stateDirectory(): string {
  const configured = process.env.XDG_STATE_HOME;
  return path.join(
    configured && path.isAbsolute(configured)
      ? configured
      : path.join(os.homedir(), ".local", "state"),
    "pi",
    "processes",
  );
}

function now(): string {
  return new Date().toISOString();
}

function textResult(
  text: string,
  details: ProcessDetails,
): { content: [{ type: "text"; text: string }]; details: ProcessDetails } {
  return { content: [{ type: "text", text }], details };
}

function errorResult(_action: ProcessParams["action"], message: string): never {
  throw new Error(message);
}

function validateManagedRef(value: string | undefined): string | undefined {
  if (!value || value.length > 120) return undefined;
  if (UNIT_RE.test(value)) return value;
  if (ID_RE.test(value)) return `${UNIT_PREFIX}${value}`;
  return undefined;
}

async function atomicWrite(
  file: string,
  value: ProcessMetadata,
): Promise<void> {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  try {
    await fs.writeFile(temporary, `${JSON.stringify(value)}\n`, {
      mode: 0o600,
    });
    await fs.rename(temporary, file);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
  }
}

async function readMetadata(
  file: string,
): Promise<ProcessMetadata | undefined> {
  try {
    const parsed = JSON.parse(
      await fs.readFile(file, "utf8"),
    ) as Partial<ProcessMetadata>;
    if (
      !parsed ||
      typeof parsed.id !== "string" ||
      !ID_RE.test(parsed.id) ||
      typeof parsed.unit !== "string" ||
      parsed.unit !== `${UNIT_PREFIX}${parsed.id}` ||
      !UNIT_RE.test(parsed.unit)
    )
      return undefined;
    if (
      typeof parsed.sessionId !== "string" ||
      typeof parsed.cwd !== "string" ||
      typeof parsed.command !== "string"
    )
      return undefined;
    if (!parsed.notification || typeof parsed.notification.sent !== "boolean")
      return undefined;
    return parsed as ProcessMetadata;
  } catch {
    return undefined;
  }
}

async function lockOwnerIsAlive(lock: string): Promise<boolean | undefined> {
  try {
    const owner = JSON.parse(
      await fs.readFile(path.join(lock, "owner"), "utf8"),
    ) as {
      pid?: unknown;
    };
    if (!Number.isInteger(owner.pid) || (owner.pid as number) <= 0)
      return undefined;
    try {
      process.kill(owner.pid as number, 0);
      return true;
    } catch (error) {
      return (error as NodeJS.ErrnoException).code === "EPERM";
    }
  } catch {
    return undefined;
  }
}

async function withRecordLock<T>(id: string, fn: () => Promise<T>): Promise<T> {
  const lock = `${unitFile(id)}.lock`;
  const token = randomBytes(12).toString("hex");
  let acquired = false;
  let ownerWritten = false;
  try {
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        await fs.mkdir(lock);
        acquired = true;
        await fs.writeFile(
          path.join(lock, "owner"),
          `${JSON.stringify({ pid: process.pid, token, createdAt: Date.now() })}\n`,
        );
        ownerWritten = true;
        break;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        try {
          const info = await fs.stat(lock);
          const alive = await lockOwnerIsAlive(lock);
          if (
            alive === false ||
            (alive === undefined && Date.now() - info.mtimeMs > 30_000)
          ) {
            await fs.rm(lock, { recursive: true, force: true });
          }
        } catch {
          // Another process may be replacing a stale lock.
        }
        await new Promise((resolve) =>
          setTimeout(resolve, Math.min(100, 10 + attempt * 2)),
        );
      }
    }
    if (!acquired || !ownerWritten)
      throw new Error(`Timed out waiting for process metadata lock: ${id}`);
    return await fn();
  } finally {
    if (acquired) {
      try {
        if (!ownerWritten) {
          await fs.rm(lock, { recursive: true, force: true });
        } else {
          const owner = JSON.parse(
            await fs.readFile(path.join(lock, "owner"), "utf8"),
          ) as { token?: unknown };
          if (owner.token === token)
            await fs.rm(lock, { recursive: true, force: true });
        }
      } catch {
        // Never remove a lock that has already been replaced by another owner.
      }
    }
  }
}

async function updateMetadata(
  id: string,
  update: (current: ProcessMetadata) => ProcessMetadata,
): Promise<ProcessMetadata> {
  return withRecordLock(id, async () => {
    const current = await readMetadata(unitFile(id));
    if (!current) throw new Error(`Process metadata missing: ${id}`);
    const next = update(current);
    await atomicWrite(unitFile(id), next);
    return next;
  });
}

async function allMetadata(): Promise<ProcessMetadata[]> {
  try {
    const names = await fs.readdir(stateDirectory());
    const records = await Promise.all(
      names
        .filter((name) => name.endsWith(".json"))
        .map((name) => readMetadata(path.join(stateDirectory(), name))),
    );
    return records.filter(
      (record): record is ProcessMetadata => record !== undefined,
    );
  } catch {
    return [];
  }
}

async function pruneMetadata(): Promise<void> {
  const records = await allMetadata();
  await Promise.all(
    records
      .filter(
        (record) =>
          record.state !== "running" &&
          Date.now() - Date.parse(record.completedAt ?? record.updatedAt) >
            RETENTION_MS,
      )
      .map((record) =>
        fs.rm(unitFile(record.id), { force: true }).catch(() => undefined),
      ),
  );
}

async function statCwd(cwd: string): Promise<string> {
  if (!cwd || cwd.length > 4096 || !path.isAbsolute(cwd))
    throw new Error("cwd must be an absolute path");
  const resolved = await fs.realpath(cwd);
  const stat = await fs.stat(resolved);
  if (!stat.isDirectory()) throw new Error("cwd must be a directory");
  return resolved;
}

function validDescription(description: string | undefined): boolean {
  return (
    description === undefined ||
    (description.length <= 200 && !/[\u0000-\u001f\u007f]/.test(description))
  );
}

function unitFile(id: string): string {
  return path.join(stateDirectory(), `${id}.json`);
}

export default function processManager(pi: ExtensionAPI): void {
  let monitorTimer: ReturnType<typeof setInterval> | undefined;
  let monitorContext: ExtensionContext | undefined;
  let monitorGeneration = 0;

  const run = (command: string, args: string[], signal?: AbortSignal) =>
    pi.exec(command, args, { signal, timeout: 15000 });

  async function inspect(
    record: ProcessMetadata,
    signal?: AbortSignal,
  ): Promise<ProcessMetadata> {
    if (record.state !== "running") return record;
    const result = await run(
      "systemctl",
      [
        "--user",
        "show",
        `--property=ActiveState,SubState,Result,ExecMainStatus`,
        "--value",
        record.unit,
      ],
      signal,
    );
    if (result.code !== 0) {
      if (Date.now() - Date.parse(record.startedAt) < 5000) return record;
      return updateMetadata(record.id, (current) => {
        if (current.state !== "running") return current;
        const completedAt = now();
        return {
          ...current,
          state: "failed",
          updatedAt: completedAt,
          completedAt,
        };
      });
    }
    const values = result.stdout.trim().split("\n");
    const active = values[0] ?? "";
    const sub = values[1] ?? "";
    const exit = Number.parseInt(values[3] ?? "", 10);
    let state: ProcessState = "running";
    if (active === "failed") state = "failed";
    else if (sub === "exited" || active === "inactive") state = "completed";
    if (state === "running") return record;
    return updateMetadata(record.id, (current) => {
      if (current.state !== "running") return current;
      const completedAt = current.completedAt ?? now();
      return {
        ...current,
        state,
        updatedAt: completedAt,
        completedAt,
        exitCode: Number.isFinite(exit)
          ? exit
          : state === "completed"
            ? 0
            : undefined,
      };
    });
  }

  async function notifyCompleted(
    record: ProcessMetadata,
    ctx: ExtensionContext,
  ): Promise<void> {
    try {
      if (record.sessionId !== ctx.sessionManager.getSessionId()) return;
      const sentAt = now();
      let claimed = false;
      const current = await updateMetadata(record.id, (latest) => {
        if (latest.notification.sent) return latest;
        claimed = true;
        return {
          ...latest,
          notification: { sent: true, sentAt },
          updatedAt: sentAt,
        };
      });
      if (!claimed) return;

      let delivered = false;
      try {
        const status = current.state === "failed" ? "failed" : "completed";
        pi.sendMessage(
          {
            customType: "process:completed",
            content: `Background process ${current.id} ${status}${current.exitCode === undefined ? "" : ` (exit ${current.exitCode})`}: ${(current.description ?? current.command).replace(/\s+/g, " ").slice(0, 300)}`,
            display: true,
            details: current,
          },
          { triggerTurn: true, deliverAs: "followUp" },
        );
        delivered = true;
        try {
          pi.events.emit("process:completed", current);
        } catch {
          // A notification listener must not prevent transient-unit cleanup.
        }
      } finally {
        if (!delivered) {
          await updateMetadata(record.id, (latest) =>
            latest.notification.sentAt === sentAt
              ? { ...latest, notification: { sent: false }, updatedAt: now() }
              : latest,
          ).catch(() => undefined);
        }
      }

      await run("systemctl", ["--user", "stop", current.unit]).catch(
        () => undefined,
      );
      if (current.state === "failed") {
        await run("systemctl", ["--user", "reset-failed", current.unit]).catch(
          () => undefined,
        );
      }
    } catch {
      // Leave unsent completions retryable after transient/session errors.
    }
  }

  async function pollSession(
    ctx: ExtensionContext,
    generation: number,
  ): Promise<void> {
    try {
      if (generation !== monitorGeneration || monitorContext !== ctx) return;
      const sessionId = ctx.sessionManager.getSessionId();
      const records = (await allMetadata()).filter(
        (record) => record.sessionId === sessionId,
      );
      let running = 0;
      for (const record of records) {
        if (generation !== monitorGeneration || monitorContext !== ctx) return;
        const current = await inspect(record).catch(() => record);
        if (current.state === "running") running += 1;
        else await notifyCompleted(current, ctx).catch(() => undefined);
      }
      if (generation !== monitorGeneration || monitorContext !== ctx) return;
      ctx.ui.setStatus(
        "background-processes",
        running > 0 ? `󰐊 ${running}` : undefined,
      );
    } catch {
      // Session replacement can invalidate the context at any await boundary.
    }
  }

  function startMonitor(ctx: ExtensionContext): void {
    if (monitorTimer !== undefined) clearInterval(monitorTimer);
    monitorGeneration += 1;
    const generation = monitorGeneration;
    monitorContext = ctx;
    void pruneMetadata().then(() => pollSession(ctx, generation));
    monitorTimer = setInterval(
      () => void pollSession(ctx, generation),
      POLL_MS,
    );
  }

  function stopMonitor(): void {
    monitorGeneration += 1;
    if (monitorTimer !== undefined) clearInterval(monitorTimer);
    monitorTimer = undefined;
    monitorContext = undefined;
  }

  pi.on("session_start", async (_event, ctx) => startMonitor(ctx));
  pi.on("session_shutdown", async () => stopMonitor());

  async function findRecord(
    ref: string | undefined,
  ): Promise<ProcessMetadata | undefined> {
    const unit = validateManagedRef(ref);
    if (!unit) return undefined;
    const records = await allMetadata();
    return records.find((record) => record.unit === unit || record.id === ref);
  }

  async function waitFor(
    record: ProcessMetadata,
    timeoutMs: number | undefined,
    signal: AbortSignal | undefined,
  ): Promise<{ record: ProcessMetadata; timedOut: boolean }> {
    const deadline = Date.now() + (timeoutMs ?? DEFAULT_WAIT_MS);
    while (true) {
      if (signal?.aborted) throw new Error("wait aborted");
      const current = await inspect(record, signal).catch(() => record);
      if (current.state !== "running")
        return { record: current, timedOut: false };
      if (Date.now() >= deadline) return { record: current, timedOut: true };
      await new Promise<void>((resolve, reject) => {
        const cleanup = () => signal?.removeEventListener("abort", onAbort);
        const timer = setTimeout(
          () => {
            cleanup();
            resolve();
          },
          Math.min(250, deadline - Date.now()),
        );
        const onAbort = () => {
          clearTimeout(timer);
          cleanup();
          reject(new Error("wait aborted"));
        };
        if (signal) signal.addEventListener("abort", onAbort, { once: true });
      });
    }
  }

  pi.registerTool({
    name: "background_process",
    label: "Background process",
    description:
      "Manage persistent systemd user services in the background. Actions: start, list, status, logs, wait, stop.",
    promptSnippet: "Start and inspect persistent background processes",
    promptGuidelines: [
      "Starting a process always asks the user for interactive confirmation.",
      "Use the returned id for status, logs, wait, or stop.",
    ],
    parameters: ProcessParams,

    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const action = params.action;
      if (action === "start") {
        if (!ctx.hasUI)
          return errorResult(
            action,
            "interactive confirmation is required to start a process",
          );
        if (
          !params.command ||
          params.command.length > MAX_COMMAND_LENGTH ||
          /[\u0000]/.test(params.command)
        )
          return errorResult(action, "command is required and must be valid");
        if (!validDescription(params.description))
          return errorResult(action, "description contains invalid characters");
        let cwd: string;
        try {
          cwd = await statCwd(params.cwd ?? ctx.cwd);
        } catch (error) {
          return errorResult(
            action,
            error instanceof Error ? error.message : "invalid cwd",
          );
        }
        const approved = await ctx.ui.confirm(
          "Start background process?",
          `${params.command}\n\nWorking directory: ${cwd}`,
        );
        if (!approved) return errorResult(action, "start rejected by user");
        const id = `${Date.now().toString(36)}-${randomBytes(5).toString("hex")}`;
        const unit = `${UNIT_PREFIX}${id}`;
        const startedAt = now();
        let record: ProcessMetadata = {
          id,
          unit,
          sessionId: ctx.sessionManager.getSessionId(),
          cwd,
          command: params.command,
          description: params.description,
          createdAt: startedAt,
          startedAt,
          updatedAt: startedAt,
          state: "running",
          notification: { sent: false },
        };
        await atomicWrite(unitFile(id), record);
        const args = [
          "--user",
          `--unit=${unit}`,
          `--working-directory=${cwd}`,
          "--property=RemainAfterExit=yes",
          "--property=StandardOutput=journal",
          "--property=StandardError=journal",
          "--",
          "/bin/sh",
          "-lc",
          params.command,
        ];
        const launched = await run("systemd-run", args, signal);
        if (launched.code !== 0) {
          record = await updateMetadata(id, (current) => {
            const completedAt = now();
            return {
              ...current,
              state: "failed",
              exitCode: launched.code,
              completedAt,
              updatedAt: completedAt,
            };
          });
          return errorResult(
            action,
            `systemd-run failed: ${launched.stderr.trim() || launched.stdout.trim() || `exit ${launched.code}`}`,
          );
        }
        return textResult(`Started ${unit}`, { action, process: record });
      }

      if (action === "list") {
        const records = (await allMetadata())
          .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))
          .slice(0, 200);
        const currentRecords = await Promise.all(
          records.map((record) => inspect(record).catch(() => record)),
        );
        const summary = currentRecords
          .map(
            (record) =>
              `${record.id} ${record.state} ${(record.description ?? record.command).replace(/\s+/g, " ").slice(0, 300)}`,
          )
          .join("\n")
          .slice(0, 40_000);
        const publicRecords = currentRecords.map((record) => ({
          ...record,
          command: record.command.slice(0, 500),
        }));
        return textResult(summary || "No managed background processes", {
          action,
          processes: publicRecords,
        });
      }

      const record = await findRecord(params.id);
      if (!record) return errorResult(action, "managed process not found");
      if (action === "status") {
        const current = await inspect(record).catch(() => record);
        return textResult(
          `${current.unit}: ${current.state}${current.exitCode === undefined ? "" : ` (exit ${current.exitCode})`}`,
          { action, process: current },
        );
      }
      if (action === "logs") {
        const lines = params.lines ?? 100;
        const maxBytes = params.maxBytes ?? 20_000;
        const logsResult = await run(
          "journalctl",
          [
            "--user",
            `--unit=${record.unit}`,
            "--no-pager",
            "--output=cat",
            `--lines=${lines}`,
          ],
          signal,
        );
        if (logsResult.code !== 0)
          return errorResult(
            action,
            logsResult.stderr.trim() || `journalctl exited ${logsResult.code}`,
          );
        const logs = Buffer.from(logsResult.stdout, "utf8")
          .subarray(0, maxBytes)
          .toString("utf8");
        return textResult(logs || "(no logs)", {
          action,
          process: record,
          logs,
        });
      }
      if (action === "wait") {
        try {
          const waited = await waitFor(record, params.timeoutMs, signal);
          return textResult(
            waited.timedOut
              ? `Timed out waiting for ${record.unit}`
              : `${waited.record.unit}: ${waited.record.state}`,
            { action, process: waited.record, timedOut: waited.timedOut },
          );
        } catch (error) {
          return errorResult(
            action,
            error instanceof Error ? error.message : "wait aborted",
          );
        }
      }
      if (action === "stop") {
        const stoppedAt = now();
        const reserved = await updateMetadata(record.id, (current) => ({
          ...current,
          state: "stopped",
          completedAt: stoppedAt,
          updatedAt: stoppedAt,
          notification: { sent: true, sentAt: stoppedAt },
        }));
        const stopped = await run(
          "systemctl",
          ["--user", "stop", record.unit],
          signal,
        );
        if (stopped.code !== 0) {
          await updateMetadata(record.id, (current) =>
            current.notification.sentAt === stoppedAt
              ? {
                  ...current,
                  state: record.state,
                  completedAt: record.completedAt,
                  updatedAt: now(),
                  notification: record.notification,
                }
              : current,
          ).catch(() => undefined);
          return errorResult(
            action,
            stopped.stderr.trim() || `systemctl exited ${stopped.code}`,
          );
        }
        return textResult(`Stopped ${record.unit}`, {
          action,
          process: reserved,
        });
      }
      return errorResult(action, "unsupported action");
    },

    renderCall(args, theme) {
      const id = args.id ? ` ${args.id}` : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("background_process ")) +
          theme.fg("muted", `${args.action}${id}`),
        0,
        0,
      );
    },

    renderResult(result, { expanded }, theme) {
      const details = result.details as ProcessDetails | undefined;
      const content = result.content[0];
      if (!details)
        return new Text(content?.type === "text" ? content.text : "", 0, 0);
      if (details.error)
        return new Text(theme.fg("error", `Error: ${details.error}`), 0, 0);
      if (details.processes) {
        const visible = expanded
          ? details.processes
          : details.processes.slice(0, 8);
        return new Text(
          visible.length
            ? visible.map((p) => `${p.id} ${p.state}`).join("\n")
            : theme.fg("dim", "No managed background processes"),
          0,
          0,
        );
      }
      return new Text(content?.type === "text" ? content.text : "", 0, 0);
    },
  });

  pi.registerCommand("processes", {
    description: "Inspect and stop managed background processes",
    handler: async (_args, ctx) => {
      const loadCurrent = async () => {
        const records = await allMetadata();
        return Promise.all(
          records.map((record) => inspect(record).catch(() => record)),
        );
      };
      if (ctx.mode !== "tui") {
        const records = await loadCurrent();
        ctx.ui.notify(
          records.length > 0
            ? records
                .map((record) => `${record.id}: ${record.state}`)
                .join("\n")
            : "No managed background processes",
          "info",
        );
        return;
      }

      while (true) {
        const records = await loadCurrent();
        const labels = records.map(
          (record) =>
            `${record.id}  ${record.state}  ${(record.description ?? record.command).replace(/\s+/g, " ").slice(0, 120)}`,
        );
        const choice = await ctx.ui.select("Background processes", [
          ...labels,
          "Refresh",
          "Close",
        ]);
        if (!choice || choice === "Close") return;
        if (choice === "Refresh") continue;
        const record = records[labels.indexOf(choice)];
        if (!record) continue;
        const action = await ctx.ui.select(record.id, [
          "Show status",
          "Show recent logs",
          ...(record.state === "running" ? ["Stop"] : []),
          "Back",
        ]);
        if (!action || action === "Back") continue;
        if (action === "Show status") {
          ctx.ui.notify(
            `${record.unit}: ${record.state}${record.exitCode === undefined ? "" : ` (exit ${record.exitCode})`}`,
            "info",
          );
        } else if (action === "Show recent logs") {
          const result = await run("journalctl", [
            "--user",
            `--unit=${record.unit}`,
            "--no-pager",
            "--output=cat",
            "--lines=50",
          ]);
          ctx.ui.notify(
            result.code === 0
              ? result.stdout.trim() || "(no logs)"
              : result.stderr.trim() || "Unable to read logs",
            result.code === 0 ? "info" : "error",
          );
        } else if (
          action === "Stop" &&
          (await ctx.ui.confirm(
            "Stop background process?",
            record.description ?? record.command,
          ))
        ) {
          const stoppedAt = now();
          await updateMetadata(record.id, (current) => ({
            ...current,
            state: "stopped",
            completedAt: stoppedAt,
            updatedAt: stoppedAt,
            notification: { sent: true, sentAt: stoppedAt },
          }));
          const result = await run("systemctl", [
            "--user",
            "stop",
            record.unit,
          ]);
          if (result.code !== 0) {
            await updateMetadata(record.id, (current) =>
              current.notification.sentAt === stoppedAt
                ? {
                    ...current,
                    state: record.state,
                    completedAt: record.completedAt,
                    updatedAt: now(),
                    notification: record.notification,
                  }
                : current,
            ).catch(() => undefined);
            ctx.ui.notify(
              result.stderr.trim() || "Unable to stop process",
              "error",
            );
          }
        }
      }
    },
  });
}
