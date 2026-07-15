const fs = require("node:fs");
const path = require("node:path");

const target = process.argv[2];
if (!target) throw new Error("usage: patch-remote-pi.cjs <dist/index.js>");

const packagePath = path.join(path.dirname(target), "..", "package.json");
const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));
if (packageJson.version !== "0.5.4") {
  throw new Error(`remote-pi patch only supports 0.5.4, found ${packageJson.version}`);
}

let source = fs.readFileSync(target, "utf8");
let changed = false;

function replaceExact(oldText, newText, expected = 1) {
  const occurrences = source.split(oldText).length - 1;
  if (occurrences !== expected) {
    throw new Error(`remote-pi patch expected ${expected} target(s), found ${occurrences}`);
  }
  source = source.split(oldText).join(newText);
  changed = true;
}

if (!source.includes("_cachedPiSessionName")) {
  const replacements = [
    ["let _pi = null;", "let _pi = null;\nlet _cachedPiSessionName;"],
    ["const piName = _pi?.getSessionName?.();", "const piName = _cachedPiSessionName;"],
    ["const _piSessionName = _pi?.getSessionName?.();", "const _piSessionName = _cachedPiSessionName;"],
    [
      'pi.on("session_start", (_event, ctx) => {',
      'pi.on("session_start", (_event, ctx) => {\n        _pi = pi;\n        _cachedPiSessionName = pi.getSessionName?.();',
    ],
    [
      '    pi.on("turn_start", (_event, ctx) => {',
      '    pi.on("session_info_changed", (event) => {\n        _cachedPiSessionName = event.name;\n        void _syncNameFromPi();\n    });\n    pi.on("turn_start", (_event, ctx) => {',
    ],
  ];
  for (const [oldText, newText] of replacements) replaceExact(oldText, newText);
}

if (!source.includes("_relay !== relay")) {
  replaceExact(
    "    _relay?.close();\n    _relay = null;\n    _relayUrl = null;\n",
    "    // Make the relay inactive before closing it. WebSocket `close` is async, so\n" +
      "    // its callback can arrive after a session replacement starts a new relay.\n" +
      "    const relay = _relay;\n    _relay = null;\n    _relayUrl = null;\n" +
      '    _state = "idle";\n    relay?.close();\n',
  );
  replaceExact(
    '    _state = "idle";\n    _refreshFooter();\n    _emitRelayState(); // → disconnected\n',
    "    _refreshFooter();\n    _emitRelayState(); // → disconnected\n",
  );
  replaceExact(
    'function _onRelayClose() {\n    if (_state === "idle")\n        return; // already torn down (e.g. /remote-pi stop)\n',
    'function _onRelayClose(relay) {\n' +
      "    // Ignore callbacks owned by a disposed session or an older relay.\n" +
      '    if (_disposed || _state === "idle" || _relay !== relay)\n        return;\n',
  );
  replaceExact(
    '    if (_getState() === "idle")\n        return; // stopped while we were here\n',
    '    if (_disposed || _getState() === "idle")\n        return; // stopped while we were here\n',
  );
  replaceExact(
    "    // _getState() to defeat TS narrowing on the module-level let.\n" +
      '    if (_getState() === "idle")\n        return;\n',
    "    // _getState() to defeat TS narrowing on the module-level let.\n" +
      '    if (_disposed || _getState() === "idle")\n        return;\n',
  );
  replaceExact(
    '    catch {\n        if (_getState() === "idle")\n            return;\n' +
      "        _scheduleReconnect();\n        return;\n    }\n" +
      '    if (_getState() === "idle") {\n',
    '    catch {\n        if (_disposed || _getState() === "idle")\n            return;\n' +
      "        _scheduleReconnect();\n        return;\n    }\n" +
      '    if (_disposed || _getState() === "idle") {\n',
  );
  replaceExact(
    '    relay.on("close", _onRelayClose);\n',
    '    relay.on("close", () => _onRelayClose(relay));\n',
    2,
  );
  replaceExact(
    "function _emitRelayState(force = false) {\n    const status = _relayStatus();\n",
    "function _emitRelayState(force = false) {\n    if (_disposed)\n        return;\n    const status = _relayStatus();\n",
  );
  replaceExact(
    "        _disposed = true;\n        if (_meshNode) {\n",
    "        _disposed = true;\n" +
      "        // Drop session-bound handles before teardown awaits the mesh socket.\n" +
      "        _pi = null;\n        _lastCtx = null;\n        _lastEventCtx = null;\n" +
      "        if (_meshNode) {\n",
  );
}

if (!source.includes("const relayPi = _pi;")) {
  const oldText = [
    "    _pi?.sendMessage({",
    '        customType: "remote-pi:relay-state",',
    '        content: `Relay ${status}`,',
    "        details: {",
    "            status,",
    '            connected: status === "connected",',
    "            ...(_relayUrl ? { relayUrl: _relayUrl } : {}),",
    "            ...(_myRoomId ? { room: _myRoomId } : {}),",
    "        },",
    "        display: false,",
    "    });",
  ].join("\n") + "\n";
  const newText = [
    "    const relayPi = _pi;",
    "    try {",
    "        relayPi?.sendMessage({",
    '            customType: "remote-pi:relay-state",',
    '            content: `Relay ${status}`,',
    "            details: {",
    "                status,",
    '                connected: status === "connected",',
    "                ...(_relayUrl ? { relayUrl: _relayUrl } : {}),",
    "                ...(_myRoomId ? { room: _myRoomId } : {}),",
    "            },",
    "            display: false,",
    "        });",
    "    }",
    "    catch (error) {",
    "        // Relay-state reporting is observational and must never terminate Pi.",
    "        const message = error instanceof Error ? error.message : String(error);",
    "        if (!/stale after session replacement or reload/i.test(message))",
    "            console.error(`[remote-pi] relay state event failed: ${message}`);",
    "        if (_pi === relayPi)",
    "            _pi = null;",
    "    }",
  ].join("\n") + "\n";
  replaceExact(oldText, newText);
}

if (changed) fs.writeFileSync(target, source);
