import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const patcher = fileURLToPath(
  new URL("../patch-pi-markdown.cjs", import.meta.url),
);
const opening =
  '                lines.push(this.theme.codeBlockBorder(`\\`\\`\\`${token.lang || ""}`));';
const closing =
  '                lines.push(this.theme.codeBlockBorder("```"));';

async function fixture(version = "0.80.7") {
  const root = await mkdtemp(join(tmpdir(), "pi-markdown-patch-"));
  const components = join(root, "dist", "components");
  await mkdir(components, { recursive: true });
  await writeFile(
    join(root, "package.json"),
    JSON.stringify({ name: "@earendil-works/pi-tui", version }),
  );
  const target = join(components, "markdown.js");
  await writeFile(target, `${opening}\ncode\n${closing}\n`);
  return { root, target };
}

test("markdown patch replaces literal fences and is idempotent", async () => {
  const { root, target } = await fixture();
  try {
    execFileSync(process.execPath, [patcher, target]);
    const once = await readFile(target, "utf8");
    assert.match(once, /╭─\$\{language\}/);
    assert.match(once, /codeBlockBorder\("╰─"\)/);
    assert.doesNotMatch(once, /codeBlockBorder\("```"\)/);

    execFileSync(process.execPath, [patcher, target]);
    assert.equal(await readFile(target, "utf8"), once);
    assert.deepEqual((await readdir(join(root, "dist", "components"))).sort(), [
      "markdown.js",
    ]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("markdown patch rejects an incomplete patched shape", async () => {
  const { root, target } = await fixture();
  try {
    execFileSync(process.execPath, [patcher, target]);
    const patched = await readFile(target, "utf8");
    await writeFile(target, patched.replace("╰─", "```"));
    assert.throws(
      () =>
        execFileSync(process.execPath, [patcher, target], { stdio: "pipe" }),
      /incomplete patched shape/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("markdown patch rejects unsupported pi-tui versions", async () => {
  const { root, target } = await fixture("0.81.0");
  try {
    assert.throws(
      () =>
        execFileSync(process.execPath, [patcher, target], { stdio: "pipe" }),
      /only supports pi-tui 0\.80\.7/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
