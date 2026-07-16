import { StringEnum } from "@earendil-works/pi-ai";
import {
  DynamicBorder,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  Editor,
  type EditorTheme,
  type SelectItem,
  SelectList,
  Text,
} from "@earendil-works/pi-tui";
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

const OTHER = "Type something";
const DONE = "Done";

function allowsOther(params: AskQuestionParams): boolean {
  return params.allowOther !== false;
}

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

type ChoiceAnswer = {
  cancelled: boolean;
  labels: string[];
  text?: string;
  values: string[];
};

async function askChoiceWithAmend(
  params: AskQuestionParams,
  signal: AbortSignal | undefined,
  ctx: ExtensionContext,
): Promise<ChoiceAnswer> {
  const options = params.options ?? [];
  const multi = params.kind === "multi-select";

  return ctx.ui.custom<ChoiceAnswer>((tui, theme, keybindings, done) => {
    const selected = new Set<number>();
    const amended = new Map<number, string>();
    const custom: string[] = [];
    let completed = false;
    let editing = false;
    let editingOption: number | undefined;
    let highlighted = 0;
    let list: SelectList;

    const editorTheme: EditorTheme = {
      borderColor: (text) => theme.fg("accent", text),
      selectList: {
        selectedPrefix: (text) => theme.fg("accent", text),
        selectedText: (text) => theme.fg("accent", text),
        description: (text) => theme.fg("muted", text),
        scrollInfo: (text) => theme.fg("dim", text),
        noMatch: (text) => theme.fg("warning", text),
      },
    };
    const editor = new Editor(tui, editorTheme);
    const keys = (binding: Parameters<typeof keybindings.getKeys>[0]) =>
      keybindings.getKeys(binding).join("/");

    const finish = (answer: ChoiceAnswer) => {
      if (completed) return;
      completed = true;
      done(answer);
    };

    const answer = (): ChoiceAnswer => {
      const values: string[] = [];
      const labels: string[] = [];
      for (let index = 0; index < options.length; index += 1) {
        const changed = amended.get(index);
        if (changed !== undefined) {
          values.push(changed);
          labels.push(changed);
        } else if (selected.has(index)) {
          values.push(options[index].value);
          labels.push(options[index].label);
        }
      }
      values.push(...custom);
      labels.push(...custom);
      return { cancelled: false, values, labels };
    };

    const items = (): SelectItem[] => {
      const result = options.map((option, index) => {
        const changed = amended.get(index);
        const marker = multi
          ? changed !== undefined
            ? "[~] "
            : selected.has(index)
              ? "[x] "
              : "[ ] "
          : "";
        return {
          value: `option:${index}`,
          label: `${marker}${index + 1}. ${option.label}`,
          description:
            changed !== undefined ? `Edited: ${changed}` : option.description,
        };
      });
      if (allowsOther(params)) {
        result.push({
          value: "other",
          label: OTHER,
          description: "Write your own answer",
        });
      }
      if (multi) {
        result.push({
          value: "done",
          label: `${DONE} (${selected.size + amended.size + custom.length} selected)`,
          description: "Submit these answers",
        });
      }
      return result;
    };

    const rebuildList = () => {
      const currentItems = items();
      list = new SelectList(currentItems, Math.min(currentItems.length, 12), {
        selectedPrefix: (text) => theme.fg("accent", text),
        selectedText: (text) => theme.fg("accent", text),
        description: (text) => theme.fg("muted", text),
        scrollInfo: (text) => theme.fg("dim", text),
        noMatch: (text) => theme.fg("warning", text),
      });
      highlighted = Math.max(0, Math.min(highlighted, currentItems.length - 1));
      list.setSelectedIndex(highlighted);
      list.onSelectionChange = (item) => {
        const index = currentItems.findIndex(
          (candidate) => candidate.value === item.value,
        );
        if (index >= 0) highlighted = index;
      };
      list.onCancel = () => finish({ cancelled: true, values: [], labels: [] });
      list.onSelect = (item) => {
        if (item.value === "done") {
          finish(answer());
          return;
        }
        if (item.value === "other") {
          editing = true;
          editingOption = undefined;
          editor.setText("");
          tui.requestRender();
          return;
        }

        const index = Number(item.value.slice("option:".length));
        if (!Number.isInteger(index) || !options[index]) return;
        if (!multi) {
          finish({
            cancelled: false,
            values: [options[index].value],
            labels: [options[index].label],
          });
          return;
        }
        if (selected.has(index)) selected.delete(index);
        else if (amended.has(index)) amended.delete(index);
        else selected.add(index);
        rebuildList();
        tui.requestRender();
      };
    };

    const startAmending = () => {
      const item = list.getSelectedItem();
      if (!item || item.value === "done") return;
      if (item.value === "other") {
        editingOption = undefined;
        editor.setText("");
      } else {
        const index = Number(item.value.slice("option:".length));
        if (!Number.isInteger(index) || !options[index]) return;
        editingOption = index;
        editor.setText(amended.get(index) ?? options[index].label);
      }
      editing = true;
      tui.requestRender();
    };

    editor.onSubmit = (value) => {
      const text = value.trim().slice(0, 10_000);
      if (!text) {
        editing = false;
        editingOption = undefined;
        editor.setText("");
        tui.requestRender();
        return;
      }
      if (!multi) {
        finish({
          cancelled: false,
          values: [text],
          labels: [text],
          text,
        });
        return;
      }
      if (editingOption === undefined) {
        if (!custom.includes(text)) custom.push(text);
      } else {
        selected.delete(editingOption);
        amended.set(editingOption, text);
      }
      editing = false;
      editingOption = undefined;
      editor.setText("");
      rebuildList();
      tui.requestRender();
    };

    rebuildList();
    const abort = () => finish({ cancelled: true, values: [], labels: [] });
    signal?.addEventListener("abort", abort, { once: true });
    if (signal?.aborted) queueMicrotask(abort);

    return {
      get focused() {
        return editor.focused;
      },
      set focused(value: boolean) {
        editor.focused = value;
      },
      render(width: number) {
        const container = new Container();
        container.addChild(
          new DynamicBorder((text: string) => theme.fg("accent", text)),
        );
        container.addChild(new Text(theme.fg("text", params.question), 1, 0));
        container.addChild(list);
        if (editing) {
          container.addChild(
            new Text(
              theme.fg(
                "muted",
                editingOption === undefined
                  ? "Type your answer:"
                  : "Edit highlighted answer:",
              ),
              1,
              0,
            ),
          );
          container.addChild(editor);
        }
        container.addChild(
          new Text(
            theme.fg(
              "dim",
              editing
                ? `${keys("tui.input.submit")} submit answer • ${keys("tui.select.cancel")} return to choices`
                : multi
                  ? `${keys("tui.select.up")}/${keys("tui.select.down")} navigate • ${keys("tui.select.confirm")} toggle • ${keys("tui.input.tab")} to edit highlighted answer • Done submit • ${keys("tui.select.cancel")} cancel`
                  : `${keys("tui.select.up")}/${keys("tui.select.down")} navigate • ${keys("tui.select.confirm")} select • ${keys("tui.input.tab")} to edit highlighted answer • ${keys("tui.select.cancel")} cancel`,
            ),
            1,
            0,
          ),
        );
        container.addChild(
          new DynamicBorder((text: string) => theme.fg("accent", text)),
        );
        return container.render(width);
      },
      invalidate() {
        list.invalidate();
        editor.invalidate();
      },
      handleInput(data: string) {
        if (editing) {
          if (keybindings.matches(data, "tui.select.cancel")) {
            editing = false;
            editingOption = undefined;
            editor.setText("");
            tui.requestRender();
            return;
          }
          editor.handleInput(data);
          tui.requestRender();
          return;
        }
        if (keybindings.matches(data, "tui.input.tab")) {
          startAmending();
          return;
        }
        list.handleInput(data);
        tui.requestRender();
      },
      dispose() {
        signal?.removeEventListener("abort", abort);
      },
    };
  });
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
      if (ctx.mode === "tui") {
        const answer = await askChoiceWithAmend(params, signal, ctx);
        if (answer.cancelled) {
          return result("User cancelled the question.", {
            ...base,
            cancelled: true,
          });
        }
        if (params.kind === "select") {
          if (answer.text !== undefined) {
            return result(`User wrote: ${answer.text || "(empty response)"}`, {
              ...base,
              values: answer.values,
              labels: answer.labels,
              text: answer.text,
            });
          }
          return result(
            `User selected: ${answer.labels[0]} (${answer.values[0]})`,
            { ...base, values: answer.values, labels: answer.labels },
          );
        }
        return result(
          answer.labels.length
            ? `User selected: ${answer.labels.join(", ")}`
            : "User selected no options.",
          { ...base, values: answer.values, labels: answer.labels },
        );
      }

      if (params.kind === "select") {
        const displays = options.map((option, index) =>
          optionDisplay(option, index),
        );
        if (allowsOther(params)) displays.push(OTHER);
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
        if (allowsOther(params)) displays.push(OTHER);
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
