export const GIT_ACTIONS = [
  "status",
  "diff",
  "log",
  "show",
  "blame",
  "changed-files",
] as const;

export type GitAction = (typeof GIT_ACTIONS)[number];

export interface GitInspectInput {
  action: GitAction;
  paths?: string[];
  ref?: string;
  staged?: boolean;
  limit?: number;
  startLine?: number;
  endLine?: number;
}

function validateRef(ref: string | undefined): string | undefined {
  if (ref === undefined) return undefined;
  if (
    !ref ||
    ref.length > 200 ||
    ref.startsWith("-") ||
    /[\s\u0000-\u001f\u007f]/.test(ref)
  ) {
    throw new Error(
      "ref must be a non-option Git revision without whitespace or control characters",
    );
  }
  return ref;
}

function validatePaths(paths: string[] | undefined): string[] {
  const values = paths ?? [];
  if (values.length > 50)
    throw new Error("paths cannot contain more than 50 entries");
  return values.map((path) => {
    if (
      !path ||
      path.length > 1000 ||
      path.startsWith("/") ||
      path.startsWith(":") ||
      /[\u0000-\u001f\u007f]/.test(path) ||
      path.split("/").includes("..")
    ) {
      throw new Error("paths must be safe repository-relative paths");
    }
    return path;
  });
}

function revisionArgs(ref: string | undefined): string[] {
  return ref ? ["--end-of-options", ref] : [];
}

export function buildGitArgs(input: GitInspectInput): string[] {
  const ref = validateRef(input.ref);
  const paths = validatePaths(input.paths);
  const pathspec = ["--", ...paths];

  if (input.action === "status") {
    if (ref !== undefined || input.staged !== undefined)
      throw new Error("status does not accept ref or staged");
    return [
      "status",
      "--short",
      "--branch",
      "--untracked-files=all",
      ...pathspec,
    ];
  }

  if (input.action === "diff" || input.action === "changed-files") {
    if (
      input.limit !== undefined ||
      input.startLine !== undefined ||
      input.endLine !== undefined
    )
      throw new Error(`${input.action} does not accept limit or line ranges`);
    return [
      "diff",
      "--no-ext-diff",
      "--no-textconv",
      "--no-color",
      ...(input.action === "changed-files"
        ? ["--name-status", "--no-renames"]
        : []),
      ...(input.staged ? ["--cached"] : []),
      ...revisionArgs(ref),
      ...pathspec,
    ];
  }

  if (input.action === "log") {
    if (
      input.staged !== undefined ||
      input.startLine !== undefined ||
      input.endLine !== undefined
    )
      throw new Error("log does not accept staged or line ranges");
    const limit = input.limit ?? 20;
    if (!Number.isInteger(limit) || limit < 1 || limit > 100)
      throw new Error("limit must be between 1 and 100");
    return [
      "log",
      "--no-color",
      "--date=short",
      "--pretty=format:%h %ad %an %s",
      `--max-count=${limit}`,
      ...revisionArgs(ref ?? "HEAD"),
      ...pathspec,
    ];
  }

  if (input.action === "show") {
    if (
      input.staged !== undefined ||
      input.limit !== undefined ||
      input.startLine !== undefined ||
      input.endLine !== undefined
    )
      throw new Error("show does not accept staged, limit, or line ranges");
    return [
      "show",
      "--no-ext-diff",
      "--no-textconv",
      "--no-color",
      "--format=fuller",
      "--stat",
      "--patch",
      ...revisionArgs(ref ?? "HEAD"),
      ...pathspec,
    ];
  }

  if (input.staged !== undefined || input.limit !== undefined)
    throw new Error("blame does not accept staged or limit");
  if (paths.length !== 1) throw new Error("blame requires exactly one path");
  const hasStart = input.startLine !== undefined;
  const hasEnd = input.endLine !== undefined;
  if (hasStart !== hasEnd)
    throw new Error("blame requires both startLine and endLine");
  if (
    hasStart &&
    (!Number.isInteger(input.startLine) ||
      !Number.isInteger(input.endLine) ||
      input.startLine! < 1 ||
      input.endLine! < input.startLine! ||
      input.endLine! - input.startLine! > 1000)
  ) {
    throw new Error(
      "blame line range must be ordered, positive, and at most 1,001 lines",
    );
  }
  return [
    "blame",
    "--line-porcelain",
    ...(hasStart ? ["-L", `${input.startLine},${input.endLine}`] : []),
    ...(ref ? [ref] : []),
    "--",
    paths[0],
  ];
}
