import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCheckPlan,
  detectProjectTypes,
} from "../lib/project-check-core.ts";

test("project detection is deterministic for mixed roots", () => {
  assert.deepEqual(
    detectProjectTypes({
      markers: new Set([
        "pubspec.yaml",
        "package.json",
        "flake.nix",
        "Makefile",
      ]),
      flutterProject: true,
    }),
    ["flutter", "node", "nix", "make"],
  );
});

test("node checks use only fixed script names", () => {
  const scripts = new Set([
    "test",
    "lint",
    "format:check",
    "build",
    "typecheck",
    "postinstall",
  ]);
  const plan = buildCheckPlan("node", "all", {
    packageManager: "pnpm",
    packageScripts: scripts,
  });
  assert.deepEqual(
    plan.map((check) => [check.action, check.command, check.args]),
    [
      ["format-check", "pnpm", ["run", "format:check"]],
      ["lint", "pnpm", ["run", "lint"]],
      ["typecheck", "pnpm", ["run", "typecheck"]],
      ["test", "pnpm", ["run", "test"]],
      ["build", "pnpm", ["run", "build"]],
    ],
  );
  assert.equal(
    plan.some((check) => check.args.includes("postinstall")),
    false,
  );
});

test("missing node scripts are skipped rather than guessed", () => {
  assert.deepEqual(
    buildCheckPlan("node", "lint", {
      packageScripts: new Set(["test"]),
    }),
    [],
  );
});

test("Go and Nix format checks receive enumerated files", () => {
  assert.deepEqual(
    buildCheckPlan("go", "format-check", {
      goFiles: ["main.go", "internal/a.go"],
    }),
    [
      {
        action: "format-check",
        command: "gofmt",
        args: ["-l", "main.go", "internal/a.go"],
        failOnOutput: true,
      },
    ],
  );
  assert.deepEqual(
    buildCheckPlan("nix", "format-check", {
      nixFiles: ["flake.nix", "modules/a.nix"],
    }),
    [
      {
        action: "format-check",
        command: "nixfmt",
        args: ["--check", "flake.nix", "modules/a.nix"],
      },
    ],
  );
});

test("Gradle and Maven prefer wrappers only when detected", () => {
  assert.equal(
    buildCheckPlan("gradle", "test", { gradleWrapper: true })[0]?.command,
    "./gradlew",
  );
  assert.equal(buildCheckPlan("gradle", "test")[0]?.command, "gradle");
  assert.equal(
    buildCheckPlan("maven", "typecheck", { mavenWrapper: true })[0]?.command,
    "./mvnw",
  );
  assert.equal(buildCheckPlan("maven", "typecheck")[0]?.command, "mvn");
});

test("Make invokes only discovered fixed targets", () => {
  assert.deepEqual(
    buildCheckPlan("make", "all", {
      makeTargets: new Set(["test", "lint", "all", "deploy"]),
    }).map((check) => [check.action, check.args[0]]),
    [
      ["lint", "lint"],
      ["test", "test"],
      ["build", "all"],
    ],
  );
});

test("duplicate checks in all are removed", () => {
  const plan = buildCheckPlan("flutter", "all");
  assert.equal(
    plan.filter(
      (check) => check.command === "flutter" && check.args[0] === "analyze",
    ).length,
    1,
  );
});
