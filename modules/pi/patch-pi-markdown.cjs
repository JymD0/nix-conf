const fs = require("node:fs");
const path = require("node:path");

const target = process.argv[2];
if (!target)
  throw new Error("usage: patch-pi-markdown.cjs <dist/components/markdown.js>");

const packagePath = path.join(path.dirname(target), "..", "..", "package.json");
const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));
if (packageJson.version !== "0.80.7") {
  throw new Error(
    `pi markdown patch only supports pi-tui 0.80.7, found ${packageJson.version}`,
  );
}

const marker = "// nix-conf: terminal code block borders";
const originalOpening =
  '                lines.push(this.theme.codeBlockBorder(`\\`\\`\\`${token.lang || ""}`));';
const originalClosing =
  '                lines.push(this.theme.codeBlockBorder("```"));';
const patchedOpening = [
  `                ${marker}`,
  '                const language = token.lang ? ` ${token.lang}` : "";',
  "                lines.push(this.theme.codeBlockBorder(`╭─${language}`));",
].join("\n");
const patchedClosing =
  '                lines.push(this.theme.codeBlockBorder("╰─"));';

let source = fs.readFileSync(target, "utf8");
const occurrences = (text) => source.split(text).length - 1;

if (source.includes(marker)) {
  const complete =
    occurrences(patchedOpening) === 1 &&
    occurrences(patchedClosing) === 1 &&
    occurrences(originalOpening) === 0 &&
    occurrences(originalClosing) === 0;
  if (!complete) {
    throw new Error("pi markdown patch found an incomplete patched shape");
  }
  process.exit(0);
}

function replaceExact(oldText, newText) {
  const count = occurrences(oldText);
  if (count !== 1) {
    throw new Error(`pi markdown patch expected one target, found ${count}`);
  }
  source = source.replace(oldText, newText);
}

replaceExact(originalOpening, patchedOpening);
replaceExact(originalClosing, patchedClosing);

const temporary = `${target}.nix-conf-${process.pid}.tmp`;
try {
  const mode = fs.statSync(target).mode;
  fs.writeFileSync(temporary, source, { mode });
  fs.renameSync(temporary, target);
} finally {
  if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
}
