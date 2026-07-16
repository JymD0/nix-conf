import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";

const mockModules = new Map([
  [
    "@earendil-works/pi-ai",
    `export const StringEnum = (values, options) => ({ values, options });`,
  ],
  [
    "@earendil-works/pi-coding-agent",
    `export class DynamicBorder {
      render() { return ["border"]; }
      invalidate() {}
    }`,
  ],
  [
    "@earendil-works/pi-tui",
    `export class Container {
      children = [];
      addChild(child) { this.children.push(child); }
      render(width) { return this.children.flatMap((child) => child.render(width)); }
    }
    export class Editor {
      focused = false;
      text = "";
      constructor() {}
      setText(value) { this.text = value; }
      render() { return [\`EDITOR:\${this.text}\`]; }
      invalidate() {}
      handleInput(data) { if (data === "enter") this.onSubmit?.(this.text); }
    }
    export class SelectList {
      index = 0;
      constructor(items) { this.items = items; }
      setSelectedIndex(index) { this.index = index; }
      getSelectedItem() { return this.items[this.index]; }
      render() {
        return this.items.map((item, index) =>
          \`\${index === this.index ? ">" : " "} \${item.label}\${item.description ? \` - \${item.description}\` : ""}\`,
        );
      }
      invalidate() {}
      handleInput(data) {
        if (data === "down") {
          this.index = Math.min(this.index + 1, this.items.length - 1);
          this.onSelectionChange?.(this.items[this.index]);
        } else if (data === "up") {
          this.index = Math.max(this.index - 1, 0);
          this.onSelectionChange?.(this.items[this.index]);
        } else if (data === "enter") {
          this.onSelect?.(this.items[this.index]);
        } else if (data === "escape") {
          this.onCancel?.();
        }
      }
    }
    export class Text {
      constructor(text) { this.text = text; }
      setText(text) { this.text = text; }
      render() { return [this.text]; }
      invalidate() {}
    }`,
  ],
  [
    "typebox",
    `const make = (...args) => ({ args });
     export const Type = new Proxy({}, { get: () => make });`,
  ],
]);

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (mockModules.has(specifier)) {
      return { url: `ask-question-mock:${specifier}`, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    const prefix = "ask-question-mock:";
    if (url.startsWith(prefix)) {
      return {
        format: "module",
        source: mockModules.get(url.slice(prefix.length)),
        shortCircuit: true,
      };
    }
    return nextLoad(url, context);
  },
});

const { default: registerAskQuestion } =
  await import("../extensions/ask-question.ts");

let askQuestionTool: any;
registerAskQuestion({
  registerTool(tool: unknown) {
    askQuestionTool = tool;
  },
} as any);

const theme = {
  bold: (text: string) => text,
  fg: (_color: string, text: string) => text,
};
const keybindings = {
  getKeys(binding: string) {
    const names: Record<string, string> = {
      "tui.input.submit": "Enter",
      "tui.input.tab": "Tab",
      "tui.select.cancel": "Esc",
      "tui.select.confirm": "Enter",
      "tui.select.down": "Down",
      "tui.select.up": "Up",
    };
    return [names[binding] ?? binding];
  },
  matches(data: string, binding: string) {
    const inputs: Record<string, string> = {
      "tui.input.submit": "enter",
      "tui.input.tab": "tab",
      "tui.select.cancel": "escape",
      "tui.select.confirm": "enter",
      "tui.select.down": "down",
      "tui.select.up": "up",
    };
    return data === inputs[binding];
  },
};

async function renderChoice(
  kind: "select" | "multi-select",
  allowOther: boolean | undefined,
  interact?: (component: any, render: () => string) => void,
): Promise<string[]> {
  const renders: string[] = [];
  const params = {
    kind,
    question: "Choose an approach",
    options: [{ value: "recommended", label: "Recommended answer" }],
    ...(allowOther === undefined ? {} : { allowOther }),
  };
  const ctx = {
    hasUI: true,
    mode: "tui",
    ui: {
      custom(factory: any) {
        return new Promise((resolve) => {
          const component = factory(
            { requestRender() {} },
            theme,
            keybindings,
            resolve,
          );
          const render = () => component.render(100).join("\n");
          renders.push(render());
          interact?.(component, render);
          component.handleInput("escape");
          component.handleInput("escape");
        });
      },
    },
  };

  await askQuestionTool.execute("call", params, undefined, undefined, ctx);
  return renders;
}

const nonTuiOptions = [
  {
    value: "recommended",
    label: "Recommended answer",
    description: "Best default",
  },
  { value: "alternative", label: "Alternative answer" },
];

async function executeNonTuiChoice(
  kind: "select" | "multi-select",
  allowOther: boolean | undefined,
  choose: (choices: string[], call: number) => string | undefined,
  answer: (question: string, call: number) => string | undefined = () =>
    undefined,
  signal?: AbortSignal,
) {
  const selectCalls: Array<{ choices: string[]; signal: AbortSignal }> = [];
  const inputCalls: Array<{ question: string; signal: AbortSignal }> = [];
  const params = {
    kind,
    question: "Choose an approach",
    options: nonTuiOptions,
    ...(allowOther === undefined ? {} : { allowOther }),
  };
  const ctx = {
    hasUI: true,
    mode: "rpc",
    ui: {
      select(_question: string, choices: string[], options: any) {
        selectCalls.push({ choices: [...choices], signal: options.signal });
        return choose(choices, selectCalls.length - 1);
      },
      input(question: string, _placeholder: string, options: any) {
        inputCalls.push({ question, signal: options.signal });
        return answer(question, inputCalls.length - 1);
      },
    },
  };

  const response = await askQuestionTool.execute(
    "call",
    params,
    signal,
    undefined,
    ctx,
  );
  return { response, selectCalls, inputCalls };
}

for (const kind of ["select", "multi-select"] as const) {
  test(`${kind} shows free text by default and honors allowOther`, async () => {
    assert.match((await renderChoice(kind, undefined))[0], /Type something/);
    assert.doesNotMatch((await renderChoice(kind, false))[0], /Type something/);
    assert.match((await renderChoice(kind, true))[0], /Type something/);
  });
}

test("footer explains that Tab edits the highlighted answer", async () => {
  const rendered = (await renderChoice("select", undefined))[0];
  assert.match(rendered, /Tab to edit highlighted answer/);
  assert.doesNotMatch(rendered, /Tab amend/);
});

test("Tab prefills the highlighted model answer", async () => {
  let editing = "";
  await renderChoice("select", undefined, (component, render) => {
    component.handleInput("tab");
    editing = render();
  });
  assert.match(editing, /Edit highlighted answer:/);
  assert.match(editing, /EDITOR:Recommended answer/);
});

test("the free-text choice opens an empty editor", async () => {
  let editing = "";
  await renderChoice("select", undefined, (component, render) => {
    component.handleInput("down");
    component.handleInput("enter");
    editing = render();
  });
  assert.match(editing, /Type your answer:/);
  assert.match(editing, /EDITOR:\n/);
  assert.doesNotMatch(editing, /EDITOR:Recommended answer/);
});

for (const kind of ["select", "multi-select"] as const) {
  test(`${kind} non-TUI choices default allowOther and honor false/true`, async () => {
    for (const [allowOther, expected] of [
      [undefined, true],
      [false, false],
      [true, true],
    ] as const) {
      const { response, selectCalls } = await executeNonTuiChoice(
        kind,
        allowOther,
        (choices) =>
          kind === "select" ? choices[0] : choices[choices.length - 1],
      );

      assert.equal(selectCalls[0].choices.includes("Type something"), expected);
      if (kind === "select") {
        assert.deepEqual(response.details.values, ["recommended"]);
        assert.deepEqual(response.details.labels, ["Recommended answer"]);
      } else {
        assert.deepEqual(response.details.values, []);
        assert.deepEqual(response.details.labels, []);
      }
    }
  });

  test(`${kind} non-TUI custom answers work when allowOther is omitted or true`, async () => {
    for (const allowOther of [undefined, true] as const) {
      const { response, selectCalls, inputCalls } = await executeNonTuiChoice(
        kind,
        allowOther,
        (choices, call) =>
          call === 0 ? "Type something" : choices[choices.length - 1],
        () => "  Custom answer  ",
      );

      assert.deepEqual(response.details.values, ["Custom answer"]);
      assert.deepEqual(response.details.labels, ["Custom answer"]);
      assert.equal(inputCalls.length, 1);
      assert.equal(selectCalls.length, kind === "select" ? 1 : 2);
      if (kind === "select")
        assert.equal(response.details.text, "Custom answer");
    }
  });
}

test("multi-select non-TUI maps toggled options in the result", async () => {
  const { response, selectCalls } = await executeNonTuiChoice(
    "multi-select",
    false,
    (choices, call) => {
      if (call === 0) return choices[1];
      assert.match(choices[1], /^\[x\] 2\. Alternative answer/);
      return choices[choices.length - 1];
    },
  );

  assert.equal(selectCalls.length, 2);
  assert.deepEqual(response.details.values, ["alternative"]);
  assert.deepEqual(response.details.labels, ["Alternative answer"]);
  assert.equal(response.content[0].text, "User selected: Alternative answer");
});

test("non-TUI choice cancellation preserves the signal and empty result", async () => {
  for (const kind of ["select", "multi-select"] as const) {
    const controller = new AbortController();
    const { response, selectCalls, inputCalls } = await executeNonTuiChoice(
      kind,
      undefined,
      () => undefined,
      undefined,
      controller.signal,
    );

    assert.equal(selectCalls[0].signal, controller.signal);
    assert.equal(inputCalls.length, 0);
    assert.equal(response.details.cancelled, true);
    assert.deepEqual(response.details.values, []);
    assert.deepEqual(response.details.labels, []);
    assert.equal(response.content[0].text, "User cancelled the question.");
  }
});
