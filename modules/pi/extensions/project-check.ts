import { StringEnum } from "@earendil-works/pi-ai";
import {
  formatSize,
  truncateHead,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type, type Static } from "typebox";
import { open, opendir, stat } from "node:fs/promises";
import { join, relative } from "node:path";

import { execBounded, type BoundedStream } from "../lib/bounded-exec.ts";
import {
  buildCheckPlan,
  CHECK_ACTIONS,
  detectProjectTypes,
  PROJECT_TYPES,
  type CheckCommand,
  type CheckContext,
  type ProjectType,
} from "../lib/project-check-core.ts";

const ProjectCheckParams = Type.Object({
  action: StringEnum(CHECK_ACTIONS, {
    description: "Check category or project detection",
  }),
  projectType: Type.Optional(
    StringEnum(PROJECT_TYPES, {
      description: "Project type override; auto uses detected markers",
    }),
  ),
  timeoutMs: Type.Optional(
    Type.Integer({
      description: "Timeout for each check in milliseconds",
      minimum: 1_000,
      maximum: 600_000,
    }),
  ),
});

type ProjectCheckParams = Static<typeof ProjectCheckParams>;
type CheckStatus = "passed" | "failed" | "unavailable";
type CheckResult = {
  action: CheckCommand["action"];
  command: string;
  args: string[];
  status: CheckStatus;
  exitCode?: number;
  durationMs: number;
  output: string;
  truncated: boolean;
};
type ProjectCheckDetails = {
  detected: ProjectType[];
  selected?: ProjectType;
  requested: ProjectCheckParams["action"];
  results: CheckResult[];
  skipped: string[];
};

const ROOT_MARKERS = [
  "pubspec.yaml",
  "Cargo.toml",
  "go.mod",
  "package.json",
  "gradlew",
  "build.gradle",
  "build.gradle.kts",
  "mvnw",
  "pom.xml",
  "pyproject.toml",
  "setup.py",
  "requirements.txt",
  "flake.nix",
  "default.nix",
  "shell.nix",
  "Makefile",
  "makefile",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lock",
  "bun.lockb",
  "package-lock.json",
] as const;

const SKIP_DIRECTORIES = new Set([
  ".git",
  ".dart_tool",
  ".gradle",
  ".idea",
  ".pi",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "result",
  "target",
  "vendor",
]);

async function markerSet(cwd: string): Promise<Set<string>> {
  const checks = await Promise.all(
    ROOT_MARKERS.map(async (marker) => {
      try {
        return (await stat(join(cwd, marker))).isFile() ? marker : undefined;
      } catch {
        return undefined;
      }
    }),
  );
  const found = new Set<string>();
  for (const marker of checks) if (marker !== undefined) found.add(marker);
  return found;
}

async function readBounded(path: string, maxBytes = 200_000): Promise<string> {
  const handle = await open(path, "r");
  try {
    const info = await handle.stat();
    if (info.size > maxBytes)
      throw new Error(`${path} is too large to inspect safely`);
    const buffer = Buffer.alloc(maxBytes + 1);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    if (bytesRead > maxBytes)
      throw new Error(`${path} grew beyond the safe inspection limit`);
    return buffer.subarray(0, bytesRead).toString("utf8");
  } finally {
    await handle.close();
  }
}

async function collectFiles(
  cwd: string,
  extension: string,
  signal?: AbortSignal,
  maxFiles = 500,
): Promise<string[]> {
  const found: string[] = [];
  let directories = 0;
  let entries = 0;
  const deadline = Date.now() + 5_000;
  const visit = async (directory: string, depth: number): Promise<void> => {
    if (signal?.aborted) throw new Error("Project file discovery aborted");
    if (depth > 20 || directories++ >= 2_000 || Date.now() > deadline)
      throw new Error("Project file discovery exceeded safe traversal limits");
    let stream;
    try {
      stream = await opendir(directory);
    } catch {
      return;
    }
    for await (const entry of stream) {
      if (signal?.aborted) throw new Error("Project file discovery aborted");
      if (++entries > 50_000 || Date.now() > deadline)
        throw new Error(
          "Project file discovery exceeded safe traversal limits",
        );
      if (entry.isSymbolicLink()) continue;
      const absolute = join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRECTORIES.has(entry.name)) await visit(absolute, depth + 1);
      } else if (entry.isFile() && entry.name.endsWith(extension)) {
        if (found.length >= maxFiles)
          throw new Error(
            `Project contains more than ${maxFiles} ${extension} files`,
          );
        found.push(relative(cwd, absolute));
      }
    }
  };
  await visit(cwd, 0);
  return found.sort();
}

async function checkContext(
  cwd: string,
  markers: Set<string>,
  selected: ProjectType,
  action: ProjectCheckParams["action"],
  signal?: AbortSignal,
): Promise<CheckContext> {
  let packageScripts = new Set<string>();
  if (markers.has("package.json")) {
    try {
      const parsed = JSON.parse(
        await readBounded(join(cwd, "package.json")),
      ) as {
        scripts?: unknown;
      };
      if (parsed.scripts && typeof parsed.scripts === "object")
        packageScripts = new Set(Object.keys(parsed.scripts));
    } catch {
      packageScripts = new Set();
    }
  }

  let makeTargets = new Set<string>();
  const makefile = markers.has("Makefile")
    ? "Makefile"
    : markers.has("makefile")
      ? "makefile"
      : undefined;
  if (makefile) {
    try {
      const source = await readBounded(join(cwd, makefile));
      makeTargets = new Set(
        [...source.matchAll(/^([A-Za-z0-9_.-]+)\s*:(?!=)/gm)]
          .map((match) => match[1])
          .filter(Boolean),
      );
    } catch {
      makeTargets = new Set();
    }
  }

  const packageManager = markers.has("pnpm-lock.yaml")
    ? "pnpm"
    : markers.has("yarn.lock")
      ? "yarn"
      : markers.has("bun.lock") || markers.has("bun.lockb")
        ? "bun"
        : "npm";

  const needsFormatFiles = action === "format-check" || action === "all";
  return {
    packageManager,
    packageScripts,
    makeTargets,
    gradleWrapper: markers.has("gradlew"),
    mavenWrapper: markers.has("mvnw"),
    goFiles:
      selected === "go" && needsFormatFiles
        ? await collectFiles(cwd, ".go", signal)
        : [],
    nixFiles:
      selected === "nix" && needsFormatFiles
        ? await collectFiles(cwd, ".nix", signal)
        : [],
  };
}

function formatCommand(command: CheckCommand): string {
  return [command.command, ...command.args]
    .map((part) =>
      /^[A-Za-z0-9_./:=@+-]+$/.test(part) ? part : JSON.stringify(part),
    )
    .join(" ");
}

function boundedCheckOutput(stdout: BoundedStream, stderr: BoundedStream) {
  const combined = [stdout.content.trimEnd(), stderr.content.trimEnd()]
    .filter(Boolean)
    .join("\n\n[stderr]\n");
  const totalBytes = stdout.totalBytes + stderr.totalBytes;
  const capturedBytes = stdout.capturedBytes + stderr.capturedBytes;
  const truncated = stdout.truncated || stderr.truncated;
  return {
    text:
      (combined || "(no output)") +
      (truncated
        ? `\n[Output truncated in memory: retained final ${formatSize(capturedBytes)} of ${formatSize(totalBytes)}]`
        : ""),
    truncated,
  };
}

export default function projectCheck(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "project_check",
    label: "Project check",
    description:
      "Detect the current project type and run bounded, structured test, lint, format-check, build, or typecheck commands. Checks may create normal build artifacts but never run formatters in write mode.",
    promptSnippet:
      "Detect and run structured project tests, linters, builds, and type checks",
    promptGuidelines: [
      "Use project_check detect before guessing project commands.",
      "Start with the narrowest relevant check and use all only when broad verification is justified.",
      "Treat failed and unavailable checks distinctly and report both honestly.",
    ],
    parameters: ProjectCheckParams,
    executionMode: "sequential",
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const markers = await markerSet(ctx.cwd);
      let flutterProject = false;
      if (markers.has("pubspec.yaml")) {
        try {
          flutterProject = /\bsdk:\s*flutter\b/.test(
            await readBounded(join(ctx.cwd, "pubspec.yaml")),
          );
        } catch {
          flutterProject = false;
        }
      }
      const detected = detectProjectTypes({ markers, flutterProject });
      const selected =
        params.projectType && params.projectType !== "auto"
          ? params.projectType
          : detected[0];
      const details: ProjectCheckDetails = {
        detected,
        selected,
        requested: params.action,
        results: [],
        skipped: [],
      };

      if (params.action === "detect") {
        const text = detected.length
          ? `Detected project types: ${detected.join(", ")}\nSelected by auto: ${selected}`
          : "No supported project type detected in the current directory.";
        return { content: [{ type: "text", text }], details };
      }
      if (!selected)
        throw new Error(
          "No supported project type detected; provide projectType explicitly or run from a project root",
        );

      const context = await checkContext(
        ctx.cwd,
        markers,
        selected,
        params.action,
        signal,
      );
      const plan = buildCheckPlan(selected, params.action, context);
      if (plan.length === 0) {
        details.skipped.push(
          `${params.action} is not configured for ${selected}`,
        );
        return {
          content: [
            {
              type: "text",
              text: `Skipped: ${params.action} is not configured for ${selected}.`,
            },
          ],
          details,
        };
      }

      for (const check of plan) {
        if (signal?.aborted) throw new Error("Project checks aborted");
        const started = performance.now();
        try {
          const execution = await execBounded(check.command, check.args, {
            cwd: ctx.cwd,
            signal,
            timeoutMs: params.timeoutMs ?? 120_000,
            maxStdoutBytes: 8_000,
            maxStderrBytes: 8_000,
            keep: "tail",
          });
          const output = boundedCheckOutput(execution.stdout, execution.stderr);
          const failedOnOutput =
            check.failOnOutput === true &&
            execution.stdout.content.trim().length > 0;
          details.results.push({
            action: check.action,
            command: check.command,
            args: check.args,
            status:
              execution.code === 0 && !failedOnOutput ? "passed" : "failed",
            exitCode: execution.code,
            durationMs: Math.round(performance.now() - started),
            output: output.text,
            truncated: output.truncated,
          });
        } catch (error) {
          if (signal?.aborted) throw new Error("Project checks aborted");
          const message =
            error instanceof Error ? error.message : String(error);
          details.results.push({
            action: check.action,
            command: check.command,
            args: check.args,
            status: /ENOENT|not found|spawn/i.test(message)
              ? "unavailable"
              : "failed",
            durationMs: Math.round(performance.now() - started),
            output: message.slice(0, 10_000),
            truncated: message.length > 10_000,
          });
        }
      }

      const sections = details.results.map((result) => {
        const heading = `${result.status.toUpperCase()} ${result.action}: ${formatCommand(result)}`;
        return `${heading}\n${result.output}`;
      });
      const aggregate = truncateHead(sections.join("\n\n"), {
        maxBytes: 40_000,
        maxLines: 1_500,
      });
      const suffix = aggregate.truncated
        ? `\n\n[Aggregate output truncated: ${formatSize(aggregate.outputBytes)} of ${formatSize(aggregate.totalBytes)}]`
        : "";
      return {
        content: [{ type: "text", text: aggregate.content + suffix }],
        details,
      };
    },
    renderCall(args, theme) {
      const project = args.projectType ? ` (${args.projectType})` : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("project_check ")) +
          theme.fg("muted", `${args.action}${project}`),
        0,
        0,
      );
    },
    renderResult(result, { expanded }, theme) {
      const details = result.details as ProjectCheckDetails | undefined;
      const content = result.content[0];
      const text = content?.type === "text" ? content.text : "";
      if (expanded || !details) return new Text(text, 0, 0);
      if (details.results.length === 0)
        return new Text(
          theme.fg("muted", text.split("\n", 1)[0] ?? "No checks"),
          0,
          0,
        );
      return new Text(
        details.results
          .map((check) => {
            const color =
              check.status === "passed"
                ? "success"
                : check.status === "failed"
                  ? "error"
                  : "warning";
            return (
              theme.fg(
                color,
                `${check.status === "passed" ? "✓" : "!"} ${check.action}`,
              ) + theme.fg("dim", ` ${check.durationMs}ms`)
            );
          })
          .join("\n"),
        0,
        0,
      );
    },
  });
}
