const { workerData, parentPort } = require('worker_threads');

function fib(n: number): number {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

parentPort.postMessage(fib(workerData as number));
