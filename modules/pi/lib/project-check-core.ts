export const PROJECT_TYPES = [
  "auto",
  "flutter",
  "dart",
  "rust",
  "go",
  "node",
  "gradle",
  "maven",
  "python",
  "nix",
  "make",
] as const;

export const CHECK_ACTIONS = [
  "detect",
  "test",
  "lint",
  "format-check",
  "build",
  "typecheck",
  "all",
] as const;

export type ProjectType = Exclude<(typeof PROJECT_TYPES)[number], "auto">;
export type CheckAction = (typeof CHECK_ACTIONS)[number];
export type PackageManager = "npm" | "pnpm" | "yarn" | "bun";

export interface DetectionInput {
  markers: ReadonlySet<string>;
  flutterProject?: boolean;
}

export interface CheckContext {
  packageManager?: PackageManager;
  packageScripts?: ReadonlySet<string>;
  makeTargets?: ReadonlySet<string>;
  gradleWrapper?: boolean;
  mavenWrapper?: boolean;
  goFiles?: string[];
  nixFiles?: string[];
}

export interface CheckCommand {
  action: Exclude<CheckAction, "detect" | "all">;
  command: string;
  args: string[];
  failOnOutput?: boolean;
}

const ACTION_ORDER: CheckCommand["action"][] = [
  "format-check",
  "lint",
  "typecheck",
  "test",
  "build",
];

export function detectProjectTypes(input: DetectionInput): ProjectType[] {
  const has = (name: string) => input.markers.has(name);
  const detected: ProjectType[] = [];
  if (has("pubspec.yaml"))
    detected.push(input.flutterProject ? "flutter" : "dart");
  if (has("Cargo.toml")) detected.push("rust");
  if (has("go.mod")) detected.push("go");
  if (has("package.json")) detected.push("node");
  if (has("gradlew") || has("build.gradle") || has("build.gradle.kts"))
    detected.push("gradle");
  if (has("mvnw") || has("pom.xml")) detected.push("maven");
  if (has("pyproject.toml") || has("setup.py") || has("requirements.txt"))
    detected.push("python");
  if (has("flake.nix") || has("default.nix") || has("shell.nix"))
    detected.push("nix");
  if (has("Makefile") || has("makefile")) detected.push("make");
  return [...new Set(detected)];
}

function nodeCommand(
  action: CheckCommand["action"],
  context: CheckContext,
): CheckCommand | undefined {
  const scripts = context.packageScripts ?? new Set<string>();
  const candidates: Record<CheckCommand["action"], string[]> = {
    test: ["test"],
    lint: ["lint"],
    "format-check": ["format:check", "format-check", "check:format"],
    build: ["build"],
    typecheck: ["typecheck", "type-check", "check:types"],
  };
  const script = candidates[action].find((candidate) => scripts.has(candidate));
  if (!script) return undefined;
  const manager = context.packageManager ?? "npm";
  return {
    action,
    command: manager,
    args: manager === "npm" ? ["run", "--silent", script] : ["run", script],
  };
}

function commandFor(
  projectType: ProjectType,
  action: CheckCommand["action"],
  context: CheckContext,
): CheckCommand | undefined {
  if (projectType === "node") return nodeCommand(action, context);

  const fixed: Partial<
    Record<
      ProjectType,
      Partial<Record<CheckCommand["action"], Omit<CheckCommand, "action">>>
    >
  > = {
    flutter: {
      test: { command: "flutter", args: ["test"] },
      lint: { command: "flutter", args: ["analyze"] },
      "format-check": {
        command: "dart",
        args: ["format", "--output=none", "--set-exit-if-changed", "."],
      },
      typecheck: { command: "flutter", args: ["analyze"] },
    },
    dart: {
      test: { command: "dart", args: ["test"] },
      lint: { command: "dart", args: ["analyze"] },
      "format-check": {
        command: "dart",
        args: ["format", "--output=none", "--set-exit-if-changed", "."],
      },
      typecheck: { command: "dart", args: ["analyze"] },
    },
    rust: {
      test: { command: "cargo", args: ["test", "--all-targets"] },
      lint: {
        command: "cargo",
        args: ["clippy", "--all-targets", "--", "-D", "warnings"],
      },
      "format-check": { command: "cargo", args: ["fmt", "--check"] },
      build: { command: "cargo", args: ["build"] },
      typecheck: { command: "cargo", args: ["check", "--all-targets"] },
    },
    go: {
      test: { command: "go", args: ["test", "./..."] },
      lint: { command: "go", args: ["vet", "./..."] },
      "format-check": context.goFiles?.length
        ? {
            command: "gofmt",
            args: ["-l", ...context.goFiles],
            failOnOutput: true,
          }
        : undefined,
      build: { command: "go", args: ["build", "./..."] },
      typecheck: { command: "go", args: ["test", "-run", "^$", "./..."] },
    },
    gradle: {
      test: {
        command: context.gradleWrapper ? "./gradlew" : "gradle",
        args: ["test", "--console=plain"],
      },
      lint: {
        command: context.gradleWrapper ? "./gradlew" : "gradle",
        args: ["check", "--console=plain"],
      },
      build: {
        command: context.gradleWrapper ? "./gradlew" : "gradle",
        args: ["build", "--console=plain"],
      },
      typecheck: {
        command: context.gradleWrapper ? "./gradlew" : "gradle",
        args: ["classes", "--console=plain"],
      },
    },
    maven: {
      test: {
        command: context.mavenWrapper ? "./mvnw" : "mvn",
        args: ["--batch-mode", "test"],
      },
      build: {
        command: context.mavenWrapper ? "./mvnw" : "mvn",
        args: ["--batch-mode", "package", "-DskipTests"],
      },
      typecheck: {
        command: context.mavenWrapper ? "./mvnw" : "mvn",
        args: ["--batch-mode", "compile"],
      },
    },
    python: {
      test: { command: "python", args: ["-m", "pytest"] },
      lint: { command: "ruff", args: ["check", "."] },
      "format-check": { command: "ruff", args: ["format", "--check", "."] },
      build: { command: "python", args: ["-m", "build"] },
      typecheck: { command: "mypy", args: ["."] },
    },
    nix: {
      test: { command: "nix", args: ["flake", "check", "--no-build"] },
      lint: { command: "statix", args: ["check", "."] },
      "format-check": context.nixFiles?.length
        ? { command: "nixfmt", args: ["--check", ...context.nixFiles] }
        : undefined,
      build: { command: "nix", args: ["flake", "check"] },
      typecheck: { command: "nix", args: ["flake", "check", "--no-build"] },
    },
  };

  if (projectType === "make") {
    const targets = context.makeTargets ?? new Set<string>();
    const candidates: Record<CheckCommand["action"], string[]> = {
      test: ["test", "check"],
      lint: ["lint"],
      "format-check": ["format-check", "check-format"],
      build: ["all", "build"],
      typecheck: ["typecheck", "check"],
    };
    const target = candidates[action].find((candidate) =>
      targets.has(candidate),
    );
    return target ? { action, command: "make", args: [target] } : undefined;
  }

  const entry = fixed[projectType]?.[action];
  if (!entry) return undefined;
  return { action, ...entry };
}

export function buildCheckPlan(
  projectType: ProjectType,
  action: Exclude<CheckAction, "detect">,
  context: CheckContext = {},
): CheckCommand[] {
  const actions = action === "all" ? ACTION_ORDER : [action];
  const commands = actions
    .map((candidate) => commandFor(projectType, candidate, context))
    .filter((command): command is CheckCommand => command !== undefined);
  const seen = new Set<string>();
  return commands.filter((command) => {
    const key = JSON.stringify([command.command, command.args]);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
