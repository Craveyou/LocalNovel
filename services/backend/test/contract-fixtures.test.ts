import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { afterEach, expect, it, vi } from "vitest";
import { decideCandidate, effectiveCandidate, type StoredCandidate } from "../src/arbitration.js";
import { progressSyncSchema, startSyncSchema, type ProgressItemInput, type ProgressSyncInput, type StartSyncInput } from "../src/schemas.js";
import { buildApp } from "../src/app.js";
import { AuthService } from "../src/auth-service.js";
import { DocumentProgressService } from "../src/document-progress.js";
import { documentSyncSchema } from "../src/document-progress.js";
import { ProgressService } from "../src/progress-service.js";
import { testConfig } from "./config-fixture.js";

function fixture<T>(name: string): T {
  return JSON.parse(readFileSync(new URL(`../../../contracts/fixtures/${name}.json`, import.meta.url), "utf8")) as T;
}
const wire = fixture<{
  ProgressSyncRequest: ProgressSyncInput;
  StartSyncRequest: StartSyncInput;
  ProgressSyncResponse: Awaited<ReturnType<ProgressService["sync"]>>;
}>("wire");
function validate(schema: string, value: unknown) {
  const result = spawnSync("ruby", [fileURLToPath(new URL("../../../scripts/contract-schema.rb", import.meta.url))], {
    input: JSON.stringify({ schema, value }), encoding: "utf8",
  });
  expect(result.status, result.stderr).toBe(0);
}
function validateCases(cases: { id: string; schema: string; value: unknown; valid: boolean }[]) {
  // Load/audit OpenAPI once, rather than spawning Ruby for every vector. Keep
  // all negative cases and fail if the validator itself cannot run.
  const result = spawnSync("ruby", ["-r", fileURLToPath(new URL("../../../scripts/contract-schema.rb", import.meta.url)),
    "-e", `validator = ContractSchema.new
puts JSON.generate(JSON.parse(STDIN.read).map do |item|
  begin
    validator.validate(item.fetch("schema"), item.fetch("value"))
    true
  rescue RuntimeError
    false
  end
end)`], { input: JSON.stringify(cases), encoding: "utf8" });
  expect(result.status, result.stderr).toBe(0);
  const actual = JSON.parse(result.stdout) as boolean[];
  expect(actual).toHaveLength(cases.length);
  cases.forEach((item, index) => expect(actual[index], item.id).toBe(item.valid));
}
afterEach(() => vi.restoreAllMocks());

it("uses the shared time-priority behavior scenarios", () => {
  for (const c of fixture<{ id: string; bookHash: string; fileSize: number; localOffset: number;
    localReadAtMs: number; remoteOffset: number; remoteReadAtMs: number; currentDeviceId: string;
    remoteDeviceId: string; expectedDecision: string }[]>("progress-behavior")) {
    const incoming = effectiveCandidate({ bookHash: c.bookHash, fileSize: c.fileSize,
      offset: c.localOffset, readAtMs: c.localReadAtMs }, 10_000);
    expect(decideCandidate({ offset: c.remoteOffset, readAtMs: c.remoteReadAtMs,
      deviceId: c.remoteDeviceId }, incoming, c.currentDeviceId), c.id).toBe(c.expectedDecision);
  }
});
it("uses service-only tie-breaking and clock-adjustment scenarios", () => {
  const cases: { id: string; stored: StoredCandidate | null; incoming: ProgressItemInput;
    serverTimeMs: number; deviceId: string; decision: string; timeAdjusted: boolean }[] = fixture("arbitration");
  for (const c of cases) {
    const candidate = effectiveCandidate(c.incoming, c.serverTimeMs);
    expect(candidate.timeAdjusted, c.id).toBe(c.timeAdjusted);
    expect(decideCandidate(c.stored ?? undefined, candidate, c.deviceId), c.id).toBe(c.decision);
  }
});
it("validates golden requests with the actual backend schemas", () => {
  expect(progressSyncSchema.parse(wire.ProgressSyncRequest)).toEqual(wire.ProgressSyncRequest);
  expect(startSyncSchema.parse(wire.StartSyncRequest)).toEqual(wire.StartSyncRequest);
  for (const c of fixture<{ id: string; schema: string; value: unknown }[]>("invalid-wire")) {
    if (c.schema === "ProgressSyncRequest") expect(progressSyncSchema.safeParse(c.value).success, c.id).toBe(false);
  }
  const item = wire.ProgressSyncRequest.items[0];
  for (const items of [[{ ...item, fileSize: 100, offset: 101 }], [item, item], [{ ...item, fileSize: 9007199254740992 }]]) {
    expect(progressSyncSchema.safeParse({ items }).success).toBe(false);
  }
});
it("validates shared comic locator vectors against OpenAPI and the backend", () => {
  const vectors = fixture<{ base: Record<string, unknown>;
    validOverrides: { overrides: Record<string, unknown> }[];
    invalidOverrides: { id: string; overrides: Record<string, unknown>; schemaInvalid: boolean }[];
  }>("comic-locators");
  const cases: Parameters<typeof validateCases>[0] = [];
  for (const vector of vectors.validOverrides) {
    const locator = { ...vectors.base, ...vector.overrides };
    cases.push({ id: "valid comic locator", schema: "ComicLocator", value: locator, valid: true },
      { id: "valid document locator", schema: "DocumentLocator", value: locator, valid: true });
    const request = { items: [{ bookHash: "a".repeat(64), fileSize: 100, locator, readAtMs: 10 }] };
    cases.push({ id: "valid comic request", schema: "DocumentProgressSyncRequest", value: request, valid: true });
    expect(documentSyncSchema.safeParse(request).success).toBe(true);
  }
  for (const vector of vectors.invalidOverrides.filter(value => value.schemaInvalid)) {
    cases.push({ id: vector.id, schema: "DocumentLocator", value: { ...vectors.base, ...vector.overrides }, valid: false });
  }
  validateCases(cases);
});
it("validates actual HTTP response envelopes against OpenAPI", async () => {
  const app = await buildApp(testConfig("postgresql://invalid:invalid@127.0.0.1:1/invalid"));
  try {
    const denied = await app.inject({ method: "GET", url: "/v1/progress" });
    expect(denied.statusCode).toBe(401);
    validate("ErrorEnvelope", denied.json());
    expect(denied.json<{ error: { code: string } }>().error.code).toBe("INVALID_SYNC_TOKEN");
    vi.spyOn(AuthService.prototype, "authenticate").mockResolvedValue({ userId: "1", userPublicId: "user",
      deviceDbId: "2", deviceId: wire.StartSyncRequest.device.deviceId,
      deviceName: "测试设备", platform: "android" });
    const sync = vi.spyOn(ProgressService.prototype, "sync").mockResolvedValue(wire.ProgressSyncResponse);
    const response = await app.inject({ method: "POST", url: "/v1/progress/sync", payload: wire.ProgressSyncRequest });
    expect(response.statusCode).toBe(200);
    expect(sync).toHaveBeenCalled();
    validate("ProgressSyncResponse", response.json());
    expect(response.json()).toEqual(wire.ProgressSyncResponse);
  } finally { await app.close(); }
});

it("validates Kindle vectors through OpenAPI, runtime schemas and the HTTP boundary", async () => {
  const vectors = fixture<{ base: Record<string, unknown>;
    validOverrides: { id: string; overrides: Record<string, unknown>; progress: number }[];
    invalidOverrides: { id: string; overrides: Record<string, unknown>; schemaInvalid?: boolean }[] }>("kindle-locators");
  const cases: Parameters<typeof validateCases>[0] = [];
  const app = await buildApp(testConfig("postgresql://invalid:invalid@127.0.0.1:1/invalid"));
  const auth = { userId: "1", userPublicId: "user", deviceDbId: "2", deviceId: wire.StartSyncRequest.device.deviceId,
    deviceName: "Kindle device", platform: "ios" as const };
  try {
    vi.spyOn(AuthService.prototype, "authenticate").mockResolvedValue(auth);
    const sync = vi.spyOn(DocumentProgressService.prototype, "sync").mockImplementation((_auth, input) => Promise.resolve({
      serverTimeMs: 1000, results: input.items.map(item => ({ decision: "accepted", timeAdjusted: false, state: {
        ...item, progress: item.locator.format === "kindle" ? item.locator.textOffset / item.locator.textLength : 0,
        version: "1", device: { deviceId: auth.deviceId, deviceName: auth.deviceName, platform: auth.platform },
      } })),
    }));
    for (const vector of [...vectors.validOverrides.map(v => ({ ...v, valid: true, schemaValid: true })),
      ...vectors.invalidOverrides.map(v => ({ ...v, valid: false, schemaValid: v.schemaInvalid === false }))]) {
      const locator = { ...vectors.base, ...vector.overrides };
      const payload = { items: [{ bookHash: "a".repeat(64), fileSize: 100, locator, readAtMs: 1000 }] };
      // OpenAPI 3.0 cannot express offset <= another property's length. The
      // runtime schema, HTTP route and PostgreSQL CHECK must still reject it.
      cases.push({ id: vector.id, schema: "KindleLocator", value: locator, valid: vector.schemaValid },
        { id: vector.id, schema: "DocumentLocator", value: locator, valid: vector.schemaValid },
        { id: vector.id, schema: "DocumentProgressSyncRequest", value: payload, valid: vector.schemaValid });
      expect(documentSyncSchema.safeParse(payload).success, vector.id).toBe(vector.valid);
      const response = await app.inject({ method: "POST", url: "/v2/progress/sync", payload });
      expect(response.statusCode, vector.id).toBe(vector.valid ? 200 : 422);
      if (vector.valid) validate("DocumentProgressState", response.json<{ results: { state: unknown }[] }>().results[0]?.state);
      else validate("ErrorEnvelope", response.json());
    }
    expect(sync).toHaveBeenCalledTimes(vectors.validOverrides.length);
    validateCases(cases);
  } finally { await app.close(); }
});

it("validates actual typed progress routes and rejects unsupported versions before storage", async () => {
  const golden = fixture<{ DocumentProgressSyncRequest: unknown; DocumentProgressState: Awaited<ReturnType<DocumentProgressService["get"]>>["items"][number] }>("wire");
  const app = await buildApp(testConfig("postgresql://invalid:invalid@127.0.0.1:1/invalid"));
  try {
    const denied = await app.inject({ method: "GET", url: `/v2/progress/${golden.DocumentProgressState.bookHash}/${golden.DocumentProgressState.fileSize}` });
    expect(denied.statusCode).toBe(401);
    vi.spyOn(AuthService.prototype, "authenticate").mockResolvedValue({ userId: "1", userPublicId: "user",
      deviceDbId: "2", deviceId: wire.StartSyncRequest.device.deviceId, deviceName: "测试设备", platform: "android" });
    const sync = vi.spyOn(DocumentProgressService.prototype, "sync").mockResolvedValue({ serverTimeMs: 1700000000000,
      results: [{ decision: "accepted", timeAdjusted: false, state: golden.DocumentProgressState }] });
    const request = documentSyncSchema.parse(golden.DocumentProgressSyncRequest);
    const response = await app.inject({ method: "POST", url: "/v2/progress/sync", payload: request });
    expect(response.statusCode).toBe(200);
    expect(sync).toHaveBeenCalledWith(expect.anything(), request);
    validate("DocumentProgressState", response.json<{results:{state:unknown}[]}>().results[0]?.state);
    const candidate = request.items[0]!;
    const invalid = { items: [{ ...candidate, locator: { ...candidate.locator, version: 2 } }] };
    expect((await app.inject({ method: "POST", url: "/v2/progress/sync", payload: invalid })).statusCode).toBe(422);
    expect(sync).toHaveBeenCalledTimes(1);
  } finally { await app.close(); }
});

it("normalizes comic uploads at the HTTP boundary and rejects unknown fields/profile without storage", async () => {
  const { base } = fixture<{ base: Record<string, unknown> }>("comic-locators");
  const app = await buildApp(testConfig("postgresql://invalid:invalid@127.0.0.1:1/invalid"));
  const auth = { userId: "1", userPublicId: "user", deviceDbId: "2", deviceId: wire.StartSyncRequest.device.deviceId,
    deviceName: "Comic device", platform: "ios" as const };
  try {
    vi.spyOn(AuthService.prototype, "authenticate").mockResolvedValue(auth);
    const sync = vi.spyOn(DocumentProgressService.prototype, "sync").mockImplementation((_auth, input) => Promise.resolve({
      serverTimeMs: 1000, results: input.items.map(item => ({ decision: "accepted", timeAdjusted: false, state: {
        ...item, progress: 1 / 3, version: "1", device: { deviceId: auth.deviceId, deviceName: auth.deviceName, platform: auth.platform },
      } })),
    }));
    for (const format of ["cbz", "cbr"]) {
      const item = { bookHash: "a".repeat(64), fileSize: 100, locator: { ...base, format, y: .5000005 }, readAtMs: 1000 };
      const response = await app.inject({ method: "POST", url: "/v2/progress/sync", payload: { items: [item] } });
      expect(response.statusCode).toBe(200);
      expect(sync).toHaveBeenLastCalledWith(auth, expect.objectContaining({ items: [expect.objectContaining({ locator: { ...base, format, y: .500001 } })] }));
      validate("DocumentProgressState", response.json<{ results: { state: unknown }[] }>().results[0]?.state);
    }
    for (const overrides of [{ profile: "comic-order-v2" }, { path: "pages/1.jpg" }, { version: 2 }, { manifestHash: "A".repeat(64) }, { page: 3 }]) {
      const response = await app.inject({ method: "POST", url: "/v2/progress/sync", payload: { items: [{
        bookHash: "a".repeat(64), fileSize: 100, locator: { ...base, ...overrides }, readAtMs: 1000,
      }] } });
      expect(response.statusCode).toBe(422);
      expect(response.json<{ error: { code: string } }>().error.code).toBe("VALIDATION_FAILED");
      validate("ErrorEnvelope", response.json());
    }
    expect(sync).toHaveBeenCalledTimes(2);
  } finally { await app.close(); }
});
