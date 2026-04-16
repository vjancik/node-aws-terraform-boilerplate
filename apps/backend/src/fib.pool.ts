// biome-ignore-all lint/correctness/noGlobalDirnameFilename: NestJS requires CommonJS
import { join } from "node:path";
import { Worker } from "node:worker_threads";

interface QueueEntry {
  n: number;
  reject: (e: Error) => void;
  resolve: (v: number) => void;
}

const isProd = __filename.endsWith(".js");
const workerFile = isProd
  ? join(__dirname, "fib.worker.js")
  : join(__dirname, "fib.worker.ts");
const workerOptions = isProd ? {} : { execArgv: ["--import", "tsx"] };

const queue: QueueEntry[] = [];
let busy = false;

const worker = new Worker(workerFile, workerOptions);

function drain() {
  if (busy || queue.length === 0) {
    return;
  }
  busy = true;
  const entry = queue.shift();
  if (!entry) {
    return;
  }
  const { n, resolve, reject } = entry;
  worker.postMessage(n);
  worker.once("message", (result: number) => {
    busy = false;
    resolve(result);
    drain();
  });
  worker.once("error", (err: Error) => {
    busy = false;
    reject(err);
    drain();
  });
}

export function runFibWorker(n: number): Promise<number> {
  return new Promise((resolve, reject) => {
    queue.push({ n, resolve, reject });
    drain();
  });
}
