import assert from "node:assert/strict";
import test from "node:test";

import {
  boundText,
  buildUserRequestText,
  cleanSessionTitle,
  formatWorkflowTitle,
  isCurrentWorkflowArtifact,
  parseWorkflowInput,
  resolveManualNameLock,
} from "../lib/session-history-core.ts";

test("session titles are normalized for safe display", () => {
  assert.equal(
    cleanSessionTitle("Title: **Fix auth retries.**"),
    "Fix auth retries",
  );
  assert.equal(
    cleanSessionTitle("\u001b]0;bad\u0007Safe session name"),
    "]0;bad Safe session name",
  );
  assert.equal(
    cleanSessionTitle("\u001bTitle: Safe session name"),
    "Safe session name",
  );
  assert.equal(cleanSessionTitle("First line\nIgnored line"), "First line");
  assert.ok(cleanSessionTitle("word ".repeat(20)).length <= 60);
});

test("automatic naming input contains only supplied user requests", () => {
  assert.equal(
    buildUserRequestText(
      [" Add auto naming ", "", "Also add a summary command"],
      1_000,
    ),
    "Add auto naming\n\n--- next user request ---\n\nAlso add a summary command",
  );
});

test("long text keeps its beginning and end", () => {
  const bounded = boundText(`start-${"x".repeat(200)}-end`, 80);
  assert.ok(bounded.startsWith("start-"));
  assert.ok(bounded.endsWith("-end"));
  assert.match(bounded, /middle omitted/);
});

test("workflow prompts expose phase, feature, and slice", () => {
  assert.deepEqual(parseWorkflowInput("/spec automatic session naming"), {
    phase: "spec",
    subject: "automatic session naming",
  });
  assert.deepEqual(
    parseWorkflowInput(
      "/implement .pi/stack-ops/plans/admin-audit-logging.plan.md implement S2 only",
    ),
    {
      phase: "implement",
      subject: "admin audit logging",
      slice: "S2",
    },
  );
  assert.equal(parseWorkflowInput("ordinary conversation"), undefined);
});

test("workflow titles include stable phase context", () => {
  assert.equal(
    formatWorkflowTitle("implement", "admin-audit-logging", "S2"),
    "Implement S2: admin audit logging",
  );
  assert.equal(
    formatWorkflowTitle("plan", "docs/specs/admin-audit-logging.md"),
    "Plan: admin audit logging",
  );
});

test("manual name provenance survives equal names and clears", () => {
  assert.equal(resolveManualNameLock(undefined, undefined, false), false);
  assert.equal(resolveManualNameLock("Auto title", "Auto title", false), false);
  assert.equal(resolveManualNameLock("Auto title", "Auto title", true), true);
  assert.equal(resolveManualNameLock(undefined, "Auto title", true), true);
});

test("workflow artifacts must belong to this session and prompt", () => {
  const startedAt = Date.parse("2026-07-15T20:00:00Z");
  assert.equal(
    isCurrentWorkflowArtifact(
      "session-a",
      "session-a",
      startedAt,
      "2026-07-15T20:00:01Z",
    ),
    true,
  );
  assert.equal(
    isCurrentWorkflowArtifact(
      "session-a",
      "session-b",
      startedAt,
      "2026-07-15T20:00:01Z",
    ),
    false,
  );
  assert.equal(
    isCurrentWorkflowArtifact(
      "session-a",
      "session-a",
      startedAt,
      "2026-07-15T19:59:59Z",
    ),
    false,
  );
});
