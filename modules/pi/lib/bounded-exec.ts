import { spawn } from "node:child_process";

export interface BoundedStream {
  content: string;
  truncated: boolean;
  capturedBytes: number;
  totalBytes: number;
  totalLines: number;
}

export interface BoundedExecResult {
  stdout: BoundedStream;
  stderr: BoundedStream;
  code: number;
  killed: boolean;
  timedOut: boolean;
}

export interface BoundedExecOptions {
  cwd: string;
  signal?: AbortSignal;
  timeoutMs: number;
  maxStdoutBytes: number;
  maxStderrBytes: number;
  keep: "head" | "tail";
}

class Capture {
  private chunks: Buffer[] = [];
  private capturedBytes = 0;
  private totalBytes = 0;
  private totalLines = 0;
  private readonly maxBytes: number;
  private readonly keep: "head" | "tail";

  constructor(maxBytes: number, keep: "head" | "tail") {
    this.maxBytes = maxBytes;
    this.keep = keep;
  }

  add(chunk: Buffer): void {
    this.totalBytes += chunk.byteLength;
    for (const byte of chunk) if (byte === 10) this.totalLines += 1;

    if (this.keep === "head") {
      const remaining = this.maxBytes - this.capturedBytes;
      if (remaining <= 0) return;
      const kept = chunk.subarray(0, remaining);
      this.chunks.push(kept);
      this.capturedBytes += kept.byteLength;
      return;
    }

    this.chunks.push(chunk);
    this.capturedBytes += chunk.byteLength;
    while (this.capturedBytes > this.maxBytes && this.chunks.length > 0) {
      const overflow = this.capturedBytes - this.maxBytes;
      const first = this.chunks[0];
      if (first.byteLength <= overflow) {
        this.chunks.shift();
        this.capturedBytes -= first.byteLength;
      } else {
        this.chunks[0] = first.subarray(overflow);
        this.capturedBytes -= overflow;
      }
    }
  }

  finish(): BoundedStream {
    const buffer = Buffer.concat(this.chunks, this.capturedBytes);
    return {
      content: buffer.toString("utf8"),
      truncated: this.totalBytes > this.capturedBytes,
      capturedBytes: this.capturedBytes,
      totalBytes: this.totalBytes,
      totalLines: this.totalLines + (this.totalBytes > 0 ? 1 : 0),
    };
  }
}

export function execBounded(
  command: string,
  args: string[],
  options: BoundedExecOptions,
): Promise<BoundedExecResult> {
  if (options.signal?.aborted)
    return Promise.reject(new Error("Operation aborted before command start"));
  return new Promise((resolve, reject) => {
    const stdout = new Capture(options.maxStdoutBytes, options.keep);
    const stderr = new Capture(options.maxStderrBytes, options.keep);
    const detached = process.platform !== "win32";
    let killed = false;
    let timedOut = false;
    let killTimer: ReturnType<typeof setTimeout> | undefined;

    const child = spawn(command, args, {
      cwd: options.cwd,
      detached,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
    });

    const sendSignal = (signal: NodeJS.Signals): void => {
      if (child.pid === undefined) return;
      try {
        if (detached) process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch {
        // The process may have exited between the state check and signal.
      }
    };
    const stop = (timeout: boolean): void => {
      if (killed) return;
      killed = true;
      timedOut = timeout;
      sendSignal("SIGTERM");
      killTimer = setTimeout(() => sendSignal("SIGKILL"), 1_000);
      killTimer.unref();
    };
    const onAbort = () => stop(false);
    const timeout = setTimeout(() => stop(true), options.timeoutMs);
    timeout.unref();
    options.signal?.addEventListener("abort", onAbort, { once: true });
    if (options.signal?.aborted) onAbort();

    child.stdout.on("data", (chunk: Buffer) => stdout.add(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.add(chunk));
    child.once("error", (error) => {
      clearTimeout(timeout);
      if (killTimer) clearTimeout(killTimer);
      options.signal?.removeEventListener("abort", onAbort);
      reject(error);
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      if (killTimer) clearTimeout(killTimer);
      options.signal?.removeEventListener("abort", onAbort);
      resolve({
        stdout: stdout.finish(),
        stderr: stderr.finish(),
        code: code ?? (killed ? 130 : 1),
        killed,
        timedOut,
      });
    });
  });
}
