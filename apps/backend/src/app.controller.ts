import { All, Controller, Get, Param } from "@nestjs/common";
import { runFibWorker } from "./fib.pool";

@Controller()
export class AppController {
  @Get("fib/:n")
  async fibonacci(@Param("n") n: string): Promise<string> {
    const num = Math.min(Number.parseInt(n, 10), 42);
    return String(await runFibWorker(num));
  }

  @Get("livez")
  livez(): string {
    return "Ok";
  }

  @Get("readyz")
  readyz(): string {
    return "Ok";
  }

  @All()
  root(): string {
    return "Ok";
  }

  @All("*path")
  rootWildcard(): string {
    return "Ok";
  }
}
