export const WORKFLOW_PHASES = [
  "spec",
  "plan-task",
  "draft",
  "discuss",
  "plan",
  "implement",
  "finish",
  "iterate",
  "merge",
] as const;
export type WorkflowPhase = (typeof WORKFLOW_PHASES)[number];
export type WorkflowHint = {
  phase: WorkflowPhase;
  subject: string;
  slice?: string;
};

const WORKFLOW_LABELS: Record<WorkflowPhase | "blocked", string> = {
  spec: "Spec",
  "plan-task": "Plan",
  draft: "Draft",
  discuss: "Discuss",
  plan: "Plan",
  implement: "Implement",
  finish: "Finish",
  iterate: "Iterate",
  merge: "Merge",
  blocked: "Blocked",
};
const STACK_PHASES = new Set<WorkflowPhase>([
  "draft",
  "discuss",
  "plan",
  "implement",
  "finish",
  "iterate",
  "merge",
]);

export function boundText(value: string, maxChars: number): string {
  if (value.length <= maxChars) return value;

  const marker = "\n\n[... middle omitted ...]\n\n";
  const side = Math.max(0, Math.floor((maxChars - marker.length) / 2));
  return `${value.slice(0, side)}${marker}${value.slice(-side)}`;
}

export function buildUserRequestText(
  requests: string[],
  maxChars: number,
): string {
  return boundText(
    requests
      .map((request) => request.trim())
      .filter(Boolean)
      .join("\n\n--- next user request ---\n\n"),
    maxChars,
  );
}

export function cleanSessionTitle(value: string): string {
  let title =
    value
      .split(/\r?\n/)
      .find((line) => line.trim())
      ?.trim() ?? "";
  title = title
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/^\s*(?:title|session (?:title|name)):\s*/i, "")
    .replace(/^[#*`'"\s]+|[#*`'"\s]+$/g, "")
    .replace(/[.!?:;,]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();

  if (title.length > 60) {
    const shortened = title.slice(0, 60);
    const wordBoundary = shortened.lastIndexOf(" ");
    title = (wordBoundary >= 30 ? shortened.slice(0, wordBoundary) : shortened)
      .replace(/[.!?:;,\-]+$/g, "")
      .trim();
  }
  return title;
}

export function parseWorkflowInput(value: string): WorkflowHint | undefined {
  const match = value.match(
    /^\/(spec|plan-task|draft|discuss|plan|implement|finish|iterate|merge)(?::\d+)?(?:\s+([\s\S]*))?$/i,
  );
  if (!match) return undefined;

  const phase = match[1].toLowerCase() as WorkflowPhase;
  const args = (match[2] ?? "").trim();
  const slice = args.match(/\bS\d+\b/i)?.[0].toUpperCase();
  return {
    phase,
    subject: extractWorkflowSubject(args),
    ...(slice ? { slice } : {}),
  };
}

export function isStackWorkflow(phase: WorkflowPhase): boolean {
  return STACK_PHASES.has(phase);
}

export function workflowLabel(
  phase: WorkflowPhase | "blocked",
  slice?: string,
): string {
  const label = WORKFLOW_LABELS[phase];
  return phase === "implement" && slice ? `${label} ${slice}` : label;
}

export function formatWorkflowTitle(
  phase: WorkflowPhase | "blocked",
  subject: string,
  slice?: string,
): string {
  const cleanSubject = humanizeIdentifier(subject);
  if (!cleanSubject) return workflowLabel(phase, slice);
  return cleanSessionTitle(`${workflowLabel(phase, slice)}: ${cleanSubject}`);
}

export function resolveManualNameLock(
  currentName: string | undefined,
  automaticName: string | undefined,
  persistedManualLock: boolean,
): boolean {
  if (persistedManualLock) return true;
  if (currentName === undefined && automaticName === undefined) return false;
  return currentName !== automaticName;
}

export function isCurrentWorkflowArtifact(
  currentSessionId: string,
  artifactSessionId: unknown,
  workflowStartedAt: number,
  artifactUpdatedAt: unknown,
): boolean {
  if (artifactSessionId !== currentSessionId) return false;
  if (typeof artifactUpdatedAt !== "string") return false;
  const updatedAt = Date.parse(artifactUpdatedAt);
  return Number.isFinite(updatedAt) && updatedAt >= workflowStartedAt;
}

export function humanizeIdentifier(value: string): string {
  const unquoted = value.trim().replace(/^['"]|['"]$/g, "");
  const pathPart = unquoted.match(
    /(?:^|\s)([^\s]+(?:\.plan)?\.md)(?:\s|$)/i,
  )?.[1];
  const candidate = pathPart ?? unquoted;
  const basename = candidate.split(/[\\/]/).pop() ?? candidate;
  return basename
    .replace(/\.plan\.md$/i, "")
    .replace(/\.md$/i, "")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractWorkflowSubject(args: string): string {
  if (!args) return "";
  const path = args.match(/(?:^|\s)([^\s]+(?:\.plan)?\.md)(?:\s|$)/i)?.[1];
  return humanizeIdentifier(path ?? args);
}
