import { Worker } from 'worker_threads';
import { join } from 'path';

type QueueEntry = { n: number; resolve: (v: number) => void; reject: (e: Error) => void };

const isProd = __filename.endsWith('.js');
const workerFile = isProd
  ? join(__dirname, 'fib.worker.js')
  : join(__dirname, 'fib.worker.ts');
const workerOptions = isProd ? {} : { execArgv: ['--import', 'tsx'] };

const queue: QueueEntry[] = [];
let busy = false;

const worker = new Worker(workerFile, workerOptions);

function drain() {
  if (busy || queue.length === 0) return;
  busy = true;
  const { n, resolve, reject } = queue.shift()!;
  worker.postMessage(n);
  worker.once('message', (result: number) => { busy = false; resolve(result); drain(); });
  worker.once('error', (err: Error) => { busy = false; reject(err); drain(); });
}

export function runFibWorker(n: number): Promise<number> {
  return new Promise((resolve, reject) => {
    queue.push({ n, resolve, reject });
    drain();
  });
}
