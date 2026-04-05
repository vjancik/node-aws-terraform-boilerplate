import { Controller, Get, All, Param } from '@nestjs/common';

function fib(n: number): number {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

@Controller()
export class AppController {
  @Get('fib/:n')
  fibonacci(@Param('n') n: string): string {
    const num = Math.min(parseInt(n, 10), 42);
    return String(fib(num));
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
