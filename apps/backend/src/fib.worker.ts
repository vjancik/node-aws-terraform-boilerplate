const { parentPort } = require('worker_threads');

function fib(n: number): number {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

parentPort.on('message', (n: number) => {
  parentPort.postMessage(fib(n));
});
