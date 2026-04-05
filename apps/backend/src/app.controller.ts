import { Controller, Get, All } from '@nestjs/common';

@Controller()
export class AppController {
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
