import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type, type Static } from "typebox";

const QUESTION_KINDS = ["select", "multi-select", "confirm", "text"] as const;

const QuestionOption = Type.Object({
  value: Type.String({
    description: "Stable value returned to the agent",
    minLength: 1,
    maxLength: 200,
  }),
  label: Type.String({
    description: "Short choice label shown to the user",
    minLength: 1,
    maxLength: 200,
  }),
  description: Type.Optional(
    Type.String({
      description: "Optional explanation or trade-off",
      maxLength: 500,
    }),
  ),
});

const AskQuestionParams = Type.Object({
  kind: StringEnum(QUESTION_KINDS, {
    description: "Interaction type",
  }),
  question: Type.String({
    description: "One focused question",
    minLength: 1,
    maxLength: 1_000,
  }),
  options: Type.Optional(
    Type.Array(QuestionOption, {
      description: "Choices for select or multi-select",
      maxItems: 12,
    }),
  ),
  allowOther: Type.Optional(
    Type.Boolean({
      description: "Allow a custom answer for select or multi-select",
    }),
  ),
  placeholder: Type.Optional(
    Type.String({ description: "Placeholder for text input", maxLength: 200 }),
  ),
});

type AskQuestionParams = Static<typeof AskQuestionParams>;
type QuestionDetails = {
  kind: AskQuestionParams["kind"];
  question: string;
  available: boolean;
  cancelled: boolean;
  values: string[];
  labels: string[];
  text?: string;
  confirmed?: boolean;
};

const OTHER = "Other: type a different answer";
const DONE = "Done";

function result(text: string, details: QuestionDetails) {
  return { content: [{ type: "text" as const, text }], details };
}

function validate(params: AskQuestionParams): void {
  const invalidControl = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;
  if (invalidControl.test(params.question))
    throw new Error("question contains unsupported control characters");
  const options = params.options ?? [];
  if (
    (params.kind === "select" || params.kind === "multi-select") &&
    options.length === 0
  ) {
    throw new Error(`${params.kind} requires at least one option`);
  }
  if (
    params.kind !== "select" &&
    params.kind !== "multi-select" &&
    options.length > 0
  ) {
    throw new Error(`${params.kind} does not accept options`);
  }
  const values = new Set<string>();
  const labels = new Set<string>();
  for (const option of options) {
    if (
      invalidControl.test(option.value) ||
      invalidControl.test(option.label) ||
      (option.description !== undefined &&
        invalidControl.test(option.description))
    ) {
      throw new Error(
        "question options contain unsupported control characters",
      );
    }
    if (values.has(option.value))
      throw new Error("option values must be unique");
    if (labels.has(option.label))
      throw new Error("option labels must be unique");
    values.add(option.value);
    labels.add(option.label);
  }
}

function optionDisplay(
  option: NonNullable<AskQuestionParams["options"]>[number],
  index: number,
  selected?: boolean,
): string {
  const mark = selected === undefined ? "" : selected ? "[x] " : "[ ] ";
  const description = option.description ? ` - ${option.description}` : "";
  return `${mark}${index + 1}. ${option.label}${description}`;
}

export default function askQuestion(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "ask_question",
    label: "Ask question",
    description:
      "Ask the user one focused select, multi-select, confirmation, or text question. Use for unresolved requirements and consequential choices, not information available from the repository.",
    promptSnippet: "Ask one adaptive requirements or decision question",
    promptGuidelines: [
      "Ask one high-value question at a time and adapt the next question to the answer.",
      "Offer concise, mutually distinct options with trade-offs and identify the recommended option in its description when appropriate.",
      "Do not ask the user for information that repository inspection can answer.",
    ],
    parameters: AskQuestionParams,
    executionMode: "sequential",
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      validate(params);
      const base: QuestionDetails = {
        kind: params.kind,
        question: params.question,
        available: ctx.hasUI,
        cancelled: false,
        values: [],
        labels: [],
      };
      if (!ctx.hasUI)
        return result(
          "Interactive questions are unavailable in this mode. Continue only with explicit assumptions or ask in plain text.",
          { ...base, cancelled: true },
        );

      if (params.kind === "confirm") {
        const confirmed = await ctx.ui.confirm("Decision", params.question, {
          signal,
        });
        return result(`User answered: ${confirmed ? "yes" : "no"}`, {
          ...base,
          confirmed,
          values: [String(confirmed)],
          labels: [confirmed ? "Yes" : "No"],
        });
      }

      if (params.kind === "text") {
        const answer = await ctx.ui.input(params.question, params.placeholder, {
          signal,
        });
        if (answer === undefined)
          return result("User cancelled the question.", {
            ...base,
            cancelled: true,
          });
        const text = answer.trim().slice(0, 10_000);
        return result(`User wrote: ${text || "(empty response)"}`, {
          ...base,
          values: [text],
          labels: [text],
          text,
        });
      }

      const options = params.options ?? [];
      if (params.kind === "select") {
        const displays = options.map((option, index) =>
          optionDisplay(option, index),
        );
        if (params.allowOther) displays.push(OTHER);
        const choice = await ctx.ui.select(params.question, displays, {
          signal,
        });
        if (choice === undefined)
          return result("User cancelled the question.", {
            ...base,
            cancelled: true,
          });
        if (choice === OTHER) {
          const custom = await ctx.ui.input("Your answer", "", { signal });
          if (custom === undefined)
            return result("User cancelled the question.", {
              ...base,
              cancelled: true,
            });
          const text = custom.trim().slice(0, 10_000);
          return result(`User wrote: ${text || "(empty response)"}`, {
            ...base,
            values: [text],
            labels: [text],
            text,
          });
        }
        const index = displays.indexOf(choice);
        const selected = options[index];
        return result(`User selected: ${selected.label} (${selected.value})`, {
          ...base,
          values: [selected.value],
          labels: [selected.label],
        });
      }

      const selected = new Set<number>();
      const custom: string[] = [];
      while (true) {
        const displays = options.map((option, index) =>
          optionDisplay(option, index, selected.has(index)),
        );
        if (params.allowOther) displays.push(OTHER);
        displays.push(`${DONE} (${selected.size + custom.length} selected)`);
        const choice = await ctx.ui.select(params.question, displays, {
          signal,
        });
        if (choice === undefined)
          return result("User cancelled the question.", {
            ...base,
            cancelled: true,
          });
        if (choice.startsWith(`${DONE} (`)) break;
        if (choice === OTHER) {
          const answer = await ctx.ui.input("Add another answer", "", {
            signal,
          });
          if (answer === undefined) continue;
          const text = answer.trim().slice(0, 10_000);
          if (text && !custom.includes(text)) custom.push(text);
          continue;
        }
        const index = displays.indexOf(choice);
        if (index < 0 || index >= options.length) continue;
        if (selected.has(index)) selected.delete(index);
        else selected.add(index);
      }
      const chosen = [...selected]
        .sort((a, b) => a - b)
        .map((index) => options[index]);
      const values = [...chosen.map((option) => option.value), ...custom];
      const labels = [...chosen.map((option) => option.label), ...custom];
      return result(
        labels.length
          ? `User selected: ${labels.join(", ")}`
          : "User selected no options.",
        { ...base, values, labels },
      );
    },
    renderCall(args, theme) {
      return new Text(
        theme.fg("toolTitle", theme.bold("ask_question ")) +
          theme.fg("muted", `${args.kind}: ${args.question}`),
        0,
        0,
      );
    },
    renderResult(toolResult, _options, theme) {
      const details = toolResult.details as QuestionDetails | undefined;
      const content = toolResult.content[0];
      const text = content?.type === "text" ? content.text : "";
      if (!details || details.cancelled)
        return new Text(theme.fg("warning", text), 0, 0);
      return new Text(
        theme.fg("success", `✓ ${details.labels.join(", ")}`),
        0,
        0,
      );
    },
  });
}
