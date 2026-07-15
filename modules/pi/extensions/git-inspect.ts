import { StringEnum } from "@earendil-works/pi-ai";
import { formatSize, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type, type Static } from "typebox";

import { execBounded } from "../lib/bounded-exec.ts";
import {
  buildGitArgs,
  GIT_ACTIONS,
  type GitInspectInput,
} from "../lib/git-inspect-core.ts";

const GitInspectParams = Type.Object({
  action: StringEnum(GIT_ACTIONS, {
    description: "Read-only Git operation",
  }),
  paths: Type.Optional(
    Type.Array(Type.String({ maxLength: 1000 }), {
      description: "Repository-relative paths",
      maxItems: 50,
    }),
  ),
  ref: Type.Optional(
    Type.String({
      description: "Git revision or revision range",
      maxLength: 200,
    }),
  ),
  staged: Type.Optional(
    Type.Boolean({ description: "Inspect staged changes for diff operations" }),
  ),
  limit: Type.Optional(
    Type.Integer({
      description: "Maximum log entries",
      minimum: 1,
      maximum: 100,
    }),
  ),
  startLine: Type.Optional(
    Type.Integer({ description: "First blame line", minimum: 1 }),
  ),
  endLine: Type.Optional(
    Type.Integer({ description: "Last blame line", minimum: 1 }),
  ),
});

type GitInspectParams = Static<typeof GitInspectParams>;

type GitInspectDetails = {
  action: GitInspectParams["action"];
  args: string[];
  exitCode: number;
  truncated: boolean;
  outputLines: number;
  totalLines: number;
};

function formatOutput(
  stdout: Awaited<ReturnType<typeof execBounded>>["stdout"],
  stderr: Awaited<ReturnType<typeof execBounded>>["stderr"],
): string {
  const combined = [stdout.content.trimEnd(), stderr.content.trimEnd()]
    .filter(Boolean)
    .join("\n\n[stderr]\n");
  const totalBytes = stdout.totalBytes + stderr.totalBytes;
  const capturedBytes = stdout.capturedBytes + stderr.capturedBytes;
  const suffix =
    stdout.truncated || stderr.truncated
      ? `\n\n[Output truncated in memory: retained ${formatSize(capturedBytes)} of ${formatSize(totalBytes)}]`
      : "";
  return (combined || "(no output)") + suffix;
}

export default function gitInspect(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "git_inspect",
    label: "Git inspect",
    description:
      "Run bounded, read-only Git inspection without a shell. Supports status, diff, log, show, blame, and changed-files.",
    promptSnippet:
      "Inspect Git status, diffs, history, commits, and blame safely",
    promptGuidelines: [
      "Prefer git_inspect over Bash for Git status, diff, log, show, blame, and changed-file inspection.",
      "Use repository-relative paths and request only the smallest relevant diff or history slice.",
    ],
    parameters: GitInspectParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const args = buildGitArgs(params as GitInspectInput);
      const execution = await execBounded("git", args, {
        cwd: ctx.cwd,
        signal,
        timeoutMs: 30_000,
        maxStdoutBytes: 35_000,
        maxStderrBytes: 5_000,
        keep: "head",
      });
      const output = formatOutput(execution.stdout, execution.stderr);
      if (execution.code !== 0)
        throw new Error(
          `git ${params.action} exited ${execution.code}: ${output}`,
        );
      const details: GitInspectDetails = {
        action: params.action,
        args,
        exitCode: execution.code,
        truncated: execution.stdout.truncated || execution.stderr.truncated,
        outputLines:
          execution.stdout.content.split("\n").length +
          execution.stderr.content.split("\n").length,
        totalLines: execution.stdout.totalLines + execution.stderr.totalLines,
      };
      return {
        content: [{ type: "text", text: output }],
        details,
      };
    },
    renderCall(args, theme) {
      const scope = args.paths?.length ? ` ${args.paths.join(", ")}` : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("git_inspect ")) +
          theme.fg("muted", `${args.action}${scope}`),
        0,
        0,
      );
    },
    renderResult(result, { expanded }, theme) {
      const details = result.details as GitInspectDetails | undefined;
      const content = result.content[0];
      const text = content?.type === "text" ? content.text : "";
      if (expanded) return new Text(text, 0, 0);
      const summary = details
        ? `${details.action}: ${details.totalLines} line(s)${details.truncated ? " (truncated)" : ""}`
        : text.split("\n", 1)[0] || "Git inspection complete";
      return new Text(theme.fg("muted", summary), 0, 0);
    },
  });
}
