import { StringEnum } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { CONFIG_DIR_NAME } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";
import { Text } from "@earendil-works/pi-tui";
import {
  mkdir,
  readFile,
  rename,
  rm,
  stat,
  writeFile,
  open,
} from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

const STATUSES = ["pending", "in_progress", "blocked", "done"] as const;
type TaskStatus = (typeof STATUSES)[number];
type Task = {
  id: string;
  title: string;
  status: TaskStatus;
  dependsOn: string[];
  notes?: string;
  createdAt: number;
  updatedAt: number;
};
type Board = { version: 1; nextId: number; tasks: Task[] };

const inputSchema = Type.Object({
  action: StringEnum(["list", "add", "update", "remove"] as const),
  id: Type.Optional(Type.String({ pattern: "^t[1-9]\\d*$" })),
  title: Type.Optional(Type.String({ maxLength: 500 })),
  status: Type.Optional(StringEnum(STATUSES)),
  dependsOn: Type.Optional(
    Type.Array(Type.String({ pattern: "^t[1-9]\\d*$" }), { maxItems: 100 }),
  ),
  notes: Type.Optional(Type.String({ maxLength: 10_000 })),
});
type ProjectTasksInput = Static<typeof inputSchema>;

type Details = {
  action: ProjectTasksInput["action"];
  tasks: Task[];
  error?: string;
  task?: Task;
};

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(new Error("Operation aborted"));
    const cleanup = () => signal?.removeEventListener("abort", onAbort);
    const timer = setTimeout(() => {
      cleanup();
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      cleanup();
      reject(new Error("Operation aborted"));
    };
    if (signal) signal.addEventListener("abort", onAbort, { once: true });
  });

function tasksPath(cwd: string): string {
  return join(cwd, CONFIG_DIR_NAME, "tasks.json");
}

function validateTask(value: unknown, now: number): Task {
  if (!value || typeof value !== "object")
    throw new Error("Invalid task entry");
  const v = value as Record<string, unknown>;
  const allowed = new Set([
    "id",
    "title",
    "status",
    "dependsOn",
    "notes",
    "createdAt",
    "updatedAt",
  ]);
  if (Object.keys(v).some((key) => !allowed.has(key)))
    throw new Error("Task contains unknown fields");
  if (typeof v.id !== "string" || !/^t[1-9]\d*$/.test(v.id))
    throw new Error("Task id must be tN");
  if (typeof v.title !== "string" || !v.title.trim() || v.title.length > 500)
    throw new Error(`Task ${v.id} has an invalid title`);
  const status = v.status === undefined ? "pending" : v.status;
  if (!STATUSES.includes(status as TaskStatus))
    throw new Error(`Task ${v.id} has an invalid status`);
  const dependsOn = v.dependsOn === undefined ? [] : v.dependsOn;
  if (
    !Array.isArray(dependsOn) ||
    dependsOn.length > 100 ||
    dependsOn.some((d) => typeof d !== "string" || !/^t[1-9]\d*$/.test(d))
  ) {
    throw new Error(`Task ${v.id} has invalid dependencies`);
  }
  if (dependsOn.includes(v.id))
    throw new Error(`Task ${v.id} cannot depend on itself`);
  if (
    v.notes !== undefined &&
    (typeof v.notes !== "string" || v.notes.length > 10_000)
  )
    throw new Error(`Task ${v.id} has invalid notes`);
  const createdAt = v.createdAt === undefined ? now : v.createdAt;
  const updatedAt = v.updatedAt === undefined ? createdAt : v.updatedAt;
  if (
    typeof createdAt !== "number" ||
    !Number.isFinite(createdAt) ||
    typeof updatedAt !== "number" ||
    !Number.isFinite(updatedAt)
  ) {
    throw new Error(`Task ${v.id} has invalid timestamps`);
  }
  return {
    id: v.id,
    title: v.title.trim(),
    status: status as TaskStatus,
    dependsOn: [...new Set(dependsOn as string[])],
    ...(v.notes === undefined ? {} : { notes: v.notes as string }),
    createdAt,
    updatedAt,
  };
}

function validateBoard(value: unknown): Board {
  const now = Date.now();
  let rawTasks: unknown;
  const version: 1 = 1;
  let rawNextId: unknown;
  if (Array.isArray(value)) rawTasks = value;
  else if (value && typeof value === "object") {
    const root = value as Record<string, unknown>;
    if (
      Object.keys(root).some(
        (key) => key !== "version" && key !== "nextId" && key !== "tasks",
      )
    )
      throw new Error("tasks.json contains unknown fields");
    if (root.version !== undefined && root.version !== 1)
      throw new Error("Unsupported tasks.json version");
    rawNextId = root.nextId;
    rawTasks = root.tasks;
    if (!Array.isArray(rawTasks))
      throw new Error("tasks.json must contain a tasks array");
  } else throw new Error("tasks.json must be an object or task array");

  if ((rawTasks as unknown[]).length > 1000)
    throw new Error("tasks.json cannot contain more than 1,000 tasks");
  const tasks = (rawTasks as unknown[]).map((task) => validateTask(task, now));
  const ids = new Set<string>();
  for (const task of tasks) {
    if (ids.has(task.id)) throw new Error(`Duplicate task id ${task.id}`);
    ids.add(task.id);
  }
  for (const task of tasks) {
    for (const dependency of task.dependsOn)
      if (!ids.has(dependency))
        throw new Error(`Task ${task.id} depends on missing ${dependency}`);
    if (
      task.status === "done" &&
      task.dependsOn.some(
        (dependency) =>
          tasks.find((candidate) => candidate.id === dependency)?.status !==
          "done",
      )
    ) {
      throw new Error(
        `Task ${task.id} is done while a dependency is incomplete`,
      );
    }
  }
  // Reject cycles: they can never be completed and usually indicate corrupt data.
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const byId = new Map(tasks.map((task) => [task.id, task]));
  const visit = (id: string) => {
    if (visiting.has(id))
      throw new Error("Circular task dependencies are not allowed");
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dependency of byId.get(id)?.dependsOn ?? []) visit(dependency);
    visiting.delete(id);
    visited.add(id);
  };
  for (const task of tasks) visit(task.id);
  const minimumNextId =
    tasks.reduce((max, task) => Math.max(max, Number(task.id.slice(1))), 0) + 1;
  const nextId = rawNextId === undefined ? minimumNextId : rawNextId;
  if (!Number.isInteger(nextId) || (nextId as number) < minimumNextId)
    throw new Error("tasks.json has an invalid nextId");
  return { version, nextId: nextId as number, tasks };
}

async function readBoard(path: string): Promise<Board> {
  let raw: string;
  try {
    raw = await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT")
      return { version: 1, nextId: 1, tasks: [] };
    throw error;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("tasks.json is malformed; refusing to overwrite it");
  }
  try {
    return validateBoard(parsed);
  } catch (error) {
    throw new Error(
      `tasks.json is invalid; refusing to overwrite it: ${(error as Error).message}`,
    );
  }
}

async function lockOwnerIsAlive(lock: string): Promise<boolean | undefined> {
  try {
    const owner = JSON.parse(await readFile(join(lock, "owner"), "utf8")) as {
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

async function withLock<T>(
  path: string,
  signal: AbortSignal | undefined,
  fn: () => Promise<T>,
): Promise<T> {
  const lock = `${path}.lock`;
  const token = randomUUID();
  await mkdir(dirname(path), { recursive: true });
  let acquired = false;
  let ownerWritten = false;
  try {
    for (let attempt = 0; attempt < 120; attempt++) {
      if (signal?.aborted) throw new Error("Operation aborted");
      try {
        await mkdir(lock);
        acquired = true;
        await writeFile(
          join(lock, "owner"),
          `${JSON.stringify({ pid: process.pid, token, createdAt: Date.now() })}\n`,
        );
        ownerWritten = true;
        break;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        try {
          const info = await stat(lock);
          const alive = await lockOwnerIsAlive(lock);
          if (
            alive === false ||
            (alive === undefined && Date.now() - info.mtimeMs > 30_000)
          ) {
            await rm(lock, { recursive: true, force: true });
          }
        } catch {
          /* another process may be replacing a stale lock */
        }
        await sleep(Math.min(250, 25 + attempt * 5), signal);
      }
    }
    if (!acquired || !ownerWritten)
      throw new Error("Timed out waiting for tasks lock");
    return await fn();
  } finally {
    if (acquired) {
      try {
        if (!ownerWritten) {
          await rm(lock, { recursive: true, force: true });
        } else {
          const owner = JSON.parse(
            await readFile(join(lock, "owner"), "utf8"),
          ) as { token?: unknown };
          if (owner.token === token)
            await rm(lock, { recursive: true, force: true });
        }
      } catch {
        // A new owner may already have replaced a stale lock; never remove it blindly.
      }
    }
  }
}

async function writeBoard(
  path: string,
  board: Board,
  signal?: AbortSignal,
): Promise<void> {
  if (signal?.aborted) throw new Error("Operation aborted");
  const dir = dirname(path);
  await mkdir(dir, { recursive: true });
  const tmp = `${path}.${process.pid}.${randomUUID()}.tmp`;
  try {
    const handle = await open(tmp, "wx", 0o600);
    try {
      await handle.writeFile(`${JSON.stringify(board, null, 2)}\n`, "utf8");
      await handle.sync();
    } finally {
      await handle.close();
    }
    if (signal?.aborted) throw new Error("Operation aborted");
    await rename(tmp, path);
  } finally {
    await rm(tmp, { force: true }).catch(() => undefined);
  }
}

async function updateStatus(ctx: ExtensionContext): Promise<void> {
  try {
    const board = await readBoard(tasksPath(ctx.cwd));
    const open = board.tasks.filter((task) => task.status !== "done").length;
    ctx.ui.setStatus("project-tasks", open > 0 ? `󰄱 ${open}` : undefined);
  } catch {
    ctx.ui.setStatus("project-tasks", "󰅙 tasks");
  }
}

function fail(_action: ProjectTasksInput["action"], error: unknown): never {
  throw error instanceof Error ? error : new Error(String(error));
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "project_tasks",
    label: "Project tasks",
    description:
      "Manage the persistent project-local shared task board in .pi/tasks.json.",
    promptSnippet: "Manage shared project tasks: list, add, update, or remove",
    promptGuidelines: [
      "Use project_tasks to claim a task before starting work, changing it to in_progress.",
      "Use project_tasks to mark completed work done and include completion notes for teammates.",
      "The project_tasks board is shared only by agents in the same checkout; the main coordinator owns updates for isolated-worktree agents.",
    ],
    parameters: inputSchema,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const action = params.action;
      try {
        const path = tasksPath(ctx.cwd);
        const result = await withLock(path, signal, async () => {
          const board = await readBoard(path);
          if (action === "list") return { board, task: undefined };
          if (action === "add") {
            if (typeof params.title !== "string" || !params.title.trim())
              throw new Error("title is required");
            const dependsOn = params.dependsOn ?? [];
            const ids = new Set(board.tasks.map((task) => task.id));
            for (const dependency of dependsOn) {
              if (dependency === "")
                throw new Error("dependency IDs cannot be empty");
              if (!ids.has(dependency))
                throw new Error(`Missing dependency ${dependency}`);
            }
            const now = Date.now();
            const task: Task = {
              id: `t${board.nextId++}`,
              title: params.title.trim(),
              status: "pending",
              dependsOn: [...new Set(dependsOn)],
              ...(params.notes === undefined ? {} : { notes: params.notes }),
              createdAt: now,
              updatedAt: now,
            };
            board.tasks.push(task);
            validateBoard(board);
            await writeBoard(path, board, signal);
            return { board, task };
          }
          if (typeof params.id !== "string" || !/^t[1-9]\d*$/.test(params.id))
            throw new Error("A valid task id (tN) is required");
          const index = board.tasks.findIndex((task) => task.id === params.id);
          if (index < 0) throw new Error(`Task ${params.id} not found`);
          if (action === "remove") {
            const dependents = board.tasks.filter((task) =>
              task.dependsOn.includes(params.id!),
            );
            if (dependents.length)
              throw new Error(
                `Cannot remove ${params.id}; dependents: ${dependents.map((task) => task.id).join(", ")}`,
              );
            const [task] = board.tasks.splice(index, 1);
            await writeBoard(path, board, signal);
            return { board, task };
          }
          const task = board.tasks[index];
          if (params.title !== undefined) {
            if (!params.title.trim()) throw new Error("title cannot be empty");
            task.title = params.title.trim();
          }
          if (params.dependsOn !== undefined) {
            const ids = new Set(board.tasks.map((item) => item.id));
            for (const dependency of params.dependsOn) {
              if (dependency === task.id)
                throw new Error("A task cannot depend on itself");
              if (!ids.has(dependency))
                throw new Error(`Missing dependency ${dependency}`);
            }
            task.dependsOn = [...new Set(params.dependsOn)];
          }
          if (params.status !== undefined && params.status === "done") {
            const incomplete = task.dependsOn.filter(
              (id) =>
                board.tasks.find((item) => item.id === id)?.status !== "done",
            );
            if (incomplete.length)
              throw new Error(
                `Cannot mark done; incomplete dependencies: ${incomplete.join(", ")}`,
              );
          }
          if (params.status !== undefined) task.status = params.status;
          if (params.notes !== undefined) task.notes = params.notes;
          task.updatedAt = Date.now();
          validateBoard(board);
          await writeBoard(path, board, signal);
          return { board, task };
        });
        await updateStatus(ctx);
        const detailTasks = result.board.tasks.slice(0, 200).map((task) => ({
          ...task,
          ...(task.notes === undefined
            ? {}
            : { notes: task.notes.slice(0, 500) }),
        }));
        const details: Details = {
          action,
          tasks: detailTasks,
          ...(result.task ? { task: result.task } : {}),
        };
        const taskList = result.board.tasks
          .map((task) => `${task.id} [${task.status}] ${task.title}`)
          .join("\n");
        const text =
          action === "list"
            ? taskList.slice(0, 40_000) || "No tasks"
            : action === "remove"
              ? `Removed ${result.task?.id}`
              : action === "add"
                ? `Added ${result.task?.id}: ${result.task?.title}`
                : `Updated ${result.task?.id}`;
        return { content: [{ type: "text", text }], details };
      } catch (error) {
        await updateStatus(ctx);
        return fail(action, error);
      }
    },
    renderCall(args, theme) {
      return new Text(
        `${theme.fg("toolTitle", theme.bold("project_tasks "))}${theme.fg("muted", args.action)}${args.id ? ` ${theme.fg("accent", args.id)}` : ""}`,
        0,
        0,
      );
    },
    renderResult(result, { expanded }, theme) {
      const details = result.details as Details | undefined;
      if (details?.error)
        return new Text(theme.fg("error", `Error: ${details.error}`), 0, 0);
      if (!details)
        return new Text(theme.fg("muted", "Task board updated"), 0, 0);
      if (details.action === "list") {
        const tasks = expanded ? details.tasks : details.tasks.slice(0, 8);
        return new Text(
          tasks.length
            ? tasks
                .map(
                  (task) =>
                    `${theme.fg(task.status === "done" ? "success" : "muted", task.id)} ${task.title} ${theme.fg("dim", `[${task.status}]`)}`,
                )
                .join("\n")
            : theme.fg("dim", "No tasks"),
          0,
          0,
        );
      }
      return new Text(
        theme.fg(
          "success",
          result.content[0]?.type === "text" ? result.content[0].text : "Done",
        ),
        0,
        0,
      );
    },
  });

  pi.registerCommand("tasks", {
    description: "Manage the shared project task board",
    handler: async (_args, ctx) => {
      const path = tasksPath(ctx.cwd);
      if (ctx.mode !== "tui") {
        try {
          const board = await readBoard(path);
          ctx.ui.notify(
            `${board.tasks.filter((task) => task.status !== "done").length} open task(s), ${board.tasks.length} total`,
            "info",
          );
        } catch (error) {
          ctx.ui.notify(
            error instanceof Error ? error.message : String(error),
            "error",
          );
        }
        return;
      }
      while (true) {
        let board: Board;
        try {
          board = await readBoard(path);
        } catch (error) {
          ctx.ui.notify(
            error instanceof Error ? error.message : String(error),
            "error",
          );
          return;
        }
        const open = board.tasks.filter(
          (task) => task.status !== "done",
        ).length;
        const choice = await ctx.ui.select(
          `Project tasks (${open} open, ${board.tasks.length} total)`,
          [
            "Add task",
            "Change status",
            "Edit notes",
            "Delete task",
            "Refresh",
            "Exit",
          ],
        );
        if (!choice || choice === "Exit") return;
        if (choice === "Refresh") continue;
        if (choice === "Add task") {
          const title = await ctx.ui.input("Task title", "");
          if (!title?.trim()) continue;
          const depsText = await ctx.ui.input(
            "Depends on IDs (comma separated, optional)",
            "",
          );
          const notes = await ctx.ui.editor("Task notes (optional)", "");
          const deps = depsText
            ?.split(",")
            .map((id) => id.trim())
            .filter(Boolean);
          try {
            await withLock(path, undefined, async () => {
              const current = await readBoard(path);
              const now = Date.now();
              current.tasks.push({
                id: `t${current.nextId++}`,
                title: title.trim(),
                status: "pending",
                dependsOn: deps ?? [],
                ...(notes ? { notes } : {}),
                createdAt: now,
                updatedAt: now,
              });
              validateBoard(current);
              await writeBoard(path, current);
            });
          } catch (error) {
            ctx.ui.notify(
              error instanceof Error ? error.message : String(error),
              "error",
            );
          }
        } else {
          if (!board.tasks.length) {
            ctx.ui.notify("No tasks", "info");
            continue;
          }
          const selected = await ctx.ui.select(
            "Select task",
            board.tasks.map(
              (task) => `${task.id}: ${task.title} [${task.status}]`,
            ),
          );
          const id = selected?.split(":", 1)[0];
          if (!id) continue;
          if (choice === "Change status") {
            const status = await ctx.ui.select("New status", [...STATUSES]);
            if (!status) continue;
            try {
              await withLock(path, undefined, async () => {
                const current = await readBoard(path);
                const task = current.tasks.find((item) => item.id === id);
                if (!task) throw new Error("Task no longer exists");
                if (
                  status === "done" &&
                  task.dependsOn.some(
                    (dep) =>
                      current.tasks.find((item) => item.id === dep)?.status !==
                      "done",
                  )
                )
                  throw new Error("Dependencies are incomplete");
                task.status = status as TaskStatus;
                task.updatedAt = Date.now();
                validateBoard(current);
                await writeBoard(path, current);
              });
            } catch (error) {
              ctx.ui.notify(
                error instanceof Error ? error.message : String(error),
                "error",
              );
            }
          } else if (choice === "Edit notes") {
            const task = board.tasks.find((item) => item.id === id);
            const notes = await ctx.ui.editor("Edit notes", task?.notes ?? "");
            if (notes === undefined) continue;
            if (notes.length > 10_000) {
              ctx.ui.notify(
                "Task notes must be 10,000 characters or fewer",
                "error",
              );
              continue;
            }
            try {
              await withLock(path, undefined, async () => {
                const current = await readBoard(path);
                const target = current.tasks.find((item) => item.id === id);
                if (!target) throw new Error("Task no longer exists");
                target.notes = notes;
                target.updatedAt = Date.now();
                validateBoard(current);
                await writeBoard(path, current);
              });
            } catch (error) {
              ctx.ui.notify(
                error instanceof Error ? error.message : String(error),
                "error",
              );
            }
          } else if (
            choice === "Delete task" &&
            (await ctx.ui.confirm("Delete task?", `Remove ${id}?`))
          ) {
            try {
              await withLock(path, undefined, async () => {
                const current = await readBoard(path);
                if (!current.tasks.some((task) => task.id === id))
                  throw new Error("Task no longer exists");
                if (current.tasks.some((task) => task.dependsOn.includes(id)))
                  throw new Error("Task has dependents");
                current.tasks = current.tasks.filter((task) => task.id !== id);
                await writeBoard(path, current);
              });
            } catch (error) {
              ctx.ui.notify(
                error instanceof Error ? error.message : String(error),
                "error",
              );
            }
          }
        }
        await updateStatus(ctx);
      }
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    await updateStatus(ctx);
  });
}
