import { Controller, Get, All, Param } from '@nestjs/common';
import { Worker } from 'worker_threads';
import { join } from 'path';

function runFibWorker(n: number): Promise<number> {
  return new Promise((resolve, reject) => {
    // In production __dirname points to compiled dist/, worker file is .js
    // In test/dev ts-jest runs TypeScript directly, so we load the .ts source via ts-node
    const isProd = __filename.endsWith('.js');
    const workerFile = isProd
      ? join(__dirname, 'fib.worker.js')
      : join(__dirname, 'fib.worker.ts');
    const workerOptions = isProd
      ? { workerData: n }
      : { workerData: n, execArgv: ['--import', 'tsx'] };

    const worker = new Worker(workerFile, workerOptions);
    worker.on('message', resolve);
    worker.on('error', reject);
  });
}

@Controller()
export class AppController {
  @Get('fib/:n')
  async fibonacci(@Param('n') n: string): Promise<string> {
    const num = Math.min(parseInt(n, 10), 42);
    return String(await runFibWorker(num));
  }

  @Get('livez')
  livez(): string {
    return 'Ok';
  }

  @Get('readyz')
  readyz(): string {
    return 'Ok';
  }

  @All()
  root(): string {
    return 'Ok';
  }

  @All('*path')
  rootWildcard(): string {
    return 'Ok';
  }
}
