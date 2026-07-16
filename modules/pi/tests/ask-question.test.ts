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
