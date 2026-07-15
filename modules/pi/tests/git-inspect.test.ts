import assert from "node:assert/strict";
import test from "node:test";

import { buildGitArgs } from "../lib/git-inspect-core.ts";

test("status uses fixed read-only arguments and path separator", () => {
  assert.deepEqual(
    buildGitArgs({ action: "status", paths: ["modules/pi.nix"] }),
    [
      "status",
      "--short",
      "--branch",
      "--untracked-files=all",
      "--",
      "modules/pi.nix",
    ],
  );
});

test("diff separates revisions and pathspecs", () => {
  assert.deepEqual(
    buildGitArgs({
      action: "diff",
      ref: "main...HEAD",
      staged: true,
      paths: ["src/file.ts"],
    }),
    [
      "diff",
      "--no-ext-diff",
      "--no-textconv",
      "--no-color",
      "--cached",
      "--end-of-options",
      "main...HEAD",
      "--",
      "src/file.ts",
    ],
  );
});

test("log has a bounded count and defaults to HEAD", () => {
  assert.deepEqual(buildGitArgs({ action: "log", limit: 7 }), [
    "log",
    "--no-color",
    "--date=short",
    "--pretty=format:%h %ad %an %s",
    "--max-count=7",
    "--end-of-options",
    "HEAD",
    "--",
  ]);
  assert.throws(
    () => buildGitArgs({ action: "log", limit: 101 }),
    /between 1 and 100/,
  );
});

test("blame accepts one bounded line range", () => {
  assert.deepEqual(
    buildGitArgs({
      action: "blame",
      ref: "HEAD~1",
      paths: ["src/main.ts"],
      startLine: 10,
      endLine: 30,
    }),
    ["blame", "--line-porcelain", "-L", "10,30", "HEAD~1", "--", "src/main.ts"],
  );
  assert.throws(
    () => buildGitArgs({ action: "blame", paths: ["a", "b"] }),
    /exactly one path/,
  );
});

test("option-like refs and escaping pathspecs are rejected", () => {
  assert.throws(
    () => buildGitArgs({ action: "show", ref: "--output=/tmp/x" }),
    /non-option Git revision/,
  );
  for (const path of ["../secret", "/etc/passwd", ":(exclude)*", "a\u0000b"]) {
    assert.throws(
      () => buildGitArgs({ action: "status", paths: [path] }),
      /safe repository-relative paths/,
    );
  }
});

test("action-specific parameters are rejected", () => {
  assert.throws(
    () => buildGitArgs({ action: "status", staged: true }),
    /does not accept/,
  );
  assert.throws(
    () => buildGitArgs({ action: "show", limit: 2 }),
    /does not accept/,
  );
});
