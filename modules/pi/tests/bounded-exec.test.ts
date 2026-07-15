import assert from "node:assert/strict";
import test from "node:test";

import { execBounded } from "../lib/bounded-exec.ts";

const cwd = process.cwd();

test("bounded execution retains only configured head bytes", async () => {
  const result = await execBounded(
    process.execPath,
    [
      "-e",
      "process.stdout.write('a'.repeat(200000)); process.stderr.write('e'.repeat(100000))",
    ],
    {
      cwd,
      timeoutMs: 5_000,
      maxStdoutBytes: 1_024,
      maxStderrBytes: 512,
      keep: "head",
    },
  );
  assert.equal(result.code, 0);
  assert.equal(result.stdout.capturedBytes, 1_024);
  assert.equal(result.stderr.capturedBytes, 512);
  assert.equal(result.stdout.totalBytes, 200_000);
  assert.equal(result.stderr.totalBytes, 100_000);
  assert.equal(result.stdout.truncated, true);
  assert.equal(result.stderr.truncated, true);
});

test("tail capture keeps the final output", async () => {
  const result = await execBounded(
    process.execPath,
    ["-e", "process.stdout.write('prefix'.repeat(1000) + 'FINAL')"],
    {
      cwd,
      timeoutMs: 5_000,
      maxStdoutBytes: 100,
      maxStderrBytes: 100,
      keep: "tail",
    },
  );
  assert.equal(result.stdout.capturedBytes, 100);
  assert.equal(result.stdout.content.endsWith("FINAL"), true);
});

test("a pre-aborted signal prevents command start", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    execBounded(process.execPath, ["-e", "process.stdout.write('started')"], {
      cwd,
      signal: controller.signal,
      timeoutMs: 5_000,
      maxStdoutBytes: 100,
      maxStderrBytes: 100,
      keep: "head",
    }),
    /aborted before command start/,
  );
});

test("timeout terminates the process group", async () => {
  const result = await execBounded(
    process.execPath,
    ["-e", "setInterval(() => {}, 1000)"],
    {
      cwd,
      timeoutMs: 50,
      maxStdoutBytes: 100,
      maxStderrBytes: 100,
      keep: "tail",
    },
  );
  assert.equal(result.killed, true);
  assert.equal(result.timedOut, true);
  assert.notEqual(result.code, 0);
});
