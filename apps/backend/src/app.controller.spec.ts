import type { INestApplication } from "@nestjs/common";
import { Test, type TestingModule } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "./app.module";

describe("AppController", () => {
  let app: INestApplication;

  beforeAll(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it("GET /fib/10 → 200 55", () =>
    request(app.getHttpServer()).get("/fib/10").expect(200).expect("55"));

  it("GET /fib/99 → capped at fib(42)", () =>
    request(app.getHttpServer())
      .get("/fib/99")
      .expect(200)
      .expect(String(267_914_296)));

  it("GET /livez → 200 Ok", () =>
    request(app.getHttpServer()).get("/livez").expect(200).expect("Ok"));

  it("GET /readyz → 200 Ok", () =>
    request(app.getHttpServer()).get("/readyz").expect(200).expect("Ok"));

  it("GET / → 200 Ok", () =>
    request(app.getHttpServer()).get("/").expect(200).expect("Ok"));

  it("POST / → 200 Ok", () =>
    request(app.getHttpServer()).post("/").expect(200).expect("Ok"));

  it("GET /some/arbitrary/path → 200 Ok", () =>
    request(app.getHttpServer())
      .get("/some/arbitrary/path")
      .expect(200)
      .expect("Ok"));
});
