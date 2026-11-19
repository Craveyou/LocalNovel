import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuthService, type StartSyncResult } from "../../src/auth-service.js";
import { IdentityRepository } from "../../src/identity-repository.js";
import { ProgressRepository } from "../../src/progress-repository.js";
import { effectiveCandidate } from "../../src/arbitration.js";
import { Database } from "../../src/database.js";
import { ProgressService } from "../../src/progress-service.js";
import { DocumentProgressService, documentSyncSchema } from "../../src/document-progress.js";
import { testConfig } from "../config-fixture.js";

const { Client } = pg;
const adminUrl = process.env.TEST_DATABASE_URL;
const appUrl = process.env.TEST_DATABASE_APP_URL;
const schema = `xlib_test_${process.pid}_${Date.now()}`;
let admin: pg.Client;
let database: Database;
let authService: AuthService;
let progressService: ProgressService;
let firstStart: StartSyncResult;
let secondStart: StartSyncResult;

function withSearchPath(url: string): string {
  const parsed = new URL(url);
  parsed.searchParams.set("options", `-c search_path=${schema}`);
  return parsed.toString();
}

async function newIdentity(label: string) {
  const registration = await authService.startSync({
    email: `${label}@example.com`,
    device: { deviceId: randomUUID(), deviceName: "Integration", platform: "ios", appVersion: "test" },
  });
  return authService.authenticate(`Bearer ${registration.token}`, registration.device.deviceId);
}

async function waitForBlockedTransaction(blocker: pg.PoolClient): Promise<void> {
  const result = await blocker.query<{ pid: number }>("select pg_backend_pid() as pid");
  const pid = result.rows[0]!.pid;
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    const blocked = await admin.query<{ blocked: boolean }>(
      `select exists(select 1 from pg_stat_activity
         where datname = current_database() and $1 = any(pg_blocking_pids(pid))) as blocked`, [pid]);
    if (blocked.rows[0]?.blocked) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error("Expected transaction did not wait on the held identity lock");
}

const integration = adminUrl ? describe : describe.skip;

integration("PostgreSQL service integration", () => {
  beforeAll(async () => {
    if (!adminUrl || !appUrl) throw new Error("Dedicated owner and application test database URLs are required");
    for (const url of [adminUrl, appUrl]) {
      if (!/(?:^|[_-])test(?:[_-]|$)/i.test(new URL(url).pathname.slice(1))) {
        throw new Error("Integration database name must contain a separate test component");
      }
    }
    admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`create schema ${schema}`);
    await admin.query(`set search_path to ${schema}`);
    for (const name of ["001_initial.sql", "002_require_fixed_sync_schema.sql", "003_document_progress.sql"]) {
      const migration = await readFile(resolve(process.cwd(), `migrations/${name}`), "utf8");
      await admin.query(migration);
    }
    const application = new Client({ connectionString: appUrl });
    await application.connect();
    let appRole: string;
    try {
      const role = await application.query<{ name: string; privileged: boolean }>(
        `select current_user as name, (rolsuper or rolcreatedb or rolcreaterole or rolbypassrls) as privileged
         from pg_roles where rolname = current_user`);
      expect(role.rows[0]?.privileged).toBe(false);
      appRole = role.rows[0]!.name;
    } finally { await application.end(); }
    const quotedRole = '"' + appRole.replaceAll('"', '""') + '"';
    await admin.query(`grant usage on schema ${schema} to ${quotedRole}`);
    await admin.query(`grant select, insert, update, delete on all tables in schema ${schema} to ${quotedRole}`);
    await admin.query(`grant usage, select on all sequences in schema ${schema} to ${quotedRole}`);
    const config = testConfig(withSearchPath(appUrl));
    database = new Database(config);
    authService = new AuthService(database, config);
    progressService = new ProgressService(database);
  });

  afterAll(async () => {
    await database?.close();
    if (admin) {
      await admin.query("set search_path to public");
      await admin.query(`drop schema ${schema} cascade`);
      await admin.end();
    }
  });

  it("upgrades 003 to 004 without changing existing TXT/PDF/EPUB rows or grants", async () => {
    const auth = await newIdentity("comic-migration");
    const service = new DocumentProgressService(database);
    await progressService.sync(auth, { items: [{ bookHash: "1".repeat(64), fileSize: 100, offset: 25, readAtMs: 1000 }] });
    await service.sync(auth, { items: [
      { bookHash: "2".repeat(64), fileSize: 200, locator: { format: "pdf", version: 1, page: 1, pageCount: 2, y: .5 }, readAtMs: 2000 },
      { bookHash: "3".repeat(64), fileSize: 300, locator: { format: "epub", version: 1, resource: "a.xhtml", spineIndex: 0, spineCount: 2, textOffset: 2, textLength: 4 }, readAtMs: 3000 },
    ] });
    const snapshot = async () => ({
      txt: (await admin.query("select * from reading_progress order by id")).rows,
      documents: (await admin.query("select * from document_progress order by user_id,book_hash,file_size")).rows,
      grants: (await admin.query("select grantee,privilege_type from information_schema.role_table_grants where table_schema=$1 and table_name='document_progress' order by grantee,privilege_type", [schema])).rows,
    });
    const before = await snapshot();
    const migration = await readFile(resolve(process.cwd(), "migrations/004_comic_progress.sql"), "utf8");
    await admin.query("begin");
    try {
      await admin.query(migration);
      await admin.query("commit");
    } catch (error) { await admin.query("rollback"); throw error; }
    expect(await snapshot()).toEqual(before);
    expect((await service.get(auth, { bookHash: "2".repeat(64), fileSize: 200 })).items[0]?.progress).toBe(.75);
    expect((await service.get(auth, { bookHash: "3".repeat(64), fileSize: 300 })).items[0]?.progress).toBe(.25);
    // Migration execution belongs to the owner, never the application role.
    await expect(database.pool.query("alter table document_progress drop constraint document_progress_locator_check"))
      .rejects.toMatchObject({ code: "42501" });
  });

  it("upgrades 004 to 005 without altering existing rows/grants, then validates Kindle as restricted role", async () => {
    const auth = await newIdentity("kindle-migration"),service = new DocumentProgressService(database);
    const snapshot = async () => ({
      rows:(await admin.query("select * from document_progress order by user_id,book_hash,file_size")).rows,
      grants:(await admin.query("select grantee,privilege_type from information_schema.role_table_grants where table_schema=$1 and table_name='document_progress' order by grantee,privilege_type",[schema])).rows,
    });
    const before = await snapshot();
    await admin.query("begin");
    try {
      await admin.query(await readFile(resolve(process.cwd(),"migrations/005_kindle_progress.sql"),"utf8"));
      await admin.query("commit");
    } catch(error) {await admin.query("rollback");throw error;}
    expect(await snapshot()).toEqual(before);
    const vectors = JSON.parse(await readFile(new URL("../../../../contracts/fixtures/kindle-locators.json",import.meta.url),"utf8")) as {base:Record<string,unknown>;invalidOverrides:{overrides:Record<string,unknown>}[]};
    const item = {bookHash:"9".repeat(64),fileSize:200,locator:vectors.base,readAtMs:1000};
    const write = (locator:unknown) => database.pool.query(`insert into document_progress(user_id,book_hash,file_size,locator,read_at,device_id,device_uid_order) values($1,decode($2,'hex'),201,$3,to_timestamp(1),$4,$5)`,[auth.userId,item.bookHash,JSON.stringify(locator),auth.deviceDbId,auth.deviceId]);
    for (const vector of vectors.invalidOverrides) await expect(write({...vectors.base,...vector.overrides})).rejects.toMatchObject({code:"23514"});
    for (const field of Object.keys(vectors.base)) {
      const missing = {...vectors.base};delete missing[field];
      await expect(write(missing)).rejects.toMatchObject({code:"23514"});
      await expect(write({...vectors.base,[field]:null})).rejects.toMatchObject({code:"23514"});
    }
    await service.sync(auth,documentSyncSchema.parse({items:[item]}));
    expect((await service.get(auth,item)).items[0]?.locator).toEqual(item.locator);
    for (const readAtMs of [500,2000]) for (const change of [{textHash:"b".repeat(64)},{textLength:41}]) {
      await expect(service.sync(auth,documentSyncSchema.parse({items:[{...item,readAtMs,locator:{...item.locator,...change}}]}))).rejects.toMatchObject({code:"VALIDATION_FAILED"});
    }
    expect((await service.get(auth,item)).items[0]?.readAtMs).toBe(1000);
    const changed = {...item,readAtMs:2000,locator:{...item.locator,textOffset:20}};
    const result = await service.sync(auth,documentSyncSchema.parse({items:[changed]}));
    expect(result.results[0]?.state.progress).toBe(.5);
    expect((await progressService.list(auth)).items).toHaveLength(0);
    await progressService.deleteBook(auth,item);
    expect((await service.get(auth,item)).items).toHaveLength(0);
  });

  it("persists CBZ/CBR as the restricted role and enforces strict comic database constraints", async () => {
    const auth = await newIdentity("comic-constraints");
    const service = new DocumentProgressService(database);
    const base = { format: "cbz", version: 1, profile: "comic-order-v1", manifestHash: "a".repeat(64),
      pageKey: "b".repeat(64), page: 0, pageCount: 3, y: 0 };
    const write = (locator: unknown) => database.pool.query(`insert into document_progress
      (user_id,book_hash,file_size,locator,read_at,device_id,device_uid_order)
      values($1,decode($2,'hex'),100,$3,to_timestamp(1),$4,$5)`,
    [auth.userId, "a".repeat(64), locator, auth.deviceDbId, auth.deviceId]);
    const vectors = JSON.parse(await readFile(new URL("../../../../contracts/fixtures/comic-locators.json", import.meta.url), "utf8")) as {
      invalidOverrides: { overrides: Record<string, unknown> }[];
    };
    const invalid: unknown[] = [null, [], "bad", {}, ...vectors.invalidOverrides.map(vector => ({ ...base, ...vector.overrides })),
      { ...base, version: "1" }, { ...base, y: .1234567 }];
    for (const field of Object.keys(base)) {
      const missing: Record<string, unknown> = { ...base };
      delete missing[field];
      invalid.push(missing);
      invalid.push({ ...base, [field]: null });
    }
    for (const locator of invalid) {
      if (locator === null) await expect(write(locator)).rejects.toMatchObject({ code: "23502" });
      else await expect(write(JSON.stringify(locator))).rejects.toMatchObject({ code: "23514" });
    }
    for (const format of ["cbz", "cbr"]) {
      const item = { bookHash: (format === "cbz" ? "c" : "d").repeat(64), fileSize: 100,
        locator: { ...base, format, y: .5000005 }, readAtMs: 1000 };
      const result = await service.sync(auth, documentSyncSchema.parse({ items: [item] }));
      expect(result.results[0]?.state.locator).toMatchObject({ format, y: .500001 });
      expect((await service.get(auth, item)).items[0]?.progress).toBe(1 / 3);
      expect((await service.get(auth, item)).items[0]?.locator).toMatchObject({ y: .500001 });
    }
    expect((await progressService.list(auth)).items).toHaveLength(0);
  });

  it("rejects incompatible comic manifests before time arbitration and rolls back the batch", async () => {
    const auth = await newIdentity("comic-conflict");
    const other = await newIdentity("comic-conflict");
    const outsider = await newIdentity("comic-outsider");
    const service = new DocumentProgressService(database);
    const item = { bookHash: "e".repeat(64), fileSize: 100, locator: {
      format: "cbz", version: 1, profile: "comic-order-v1", manifestHash: "a".repeat(64),
      pageKey: "b".repeat(64), page: 0, pageCount: 3, y: 0 }, readAtMs: 1000 };
    const sync = (items: unknown[], requester = auth) => service.sync(requester, documentSyncSchema.parse({ items }));
    await sync([item]);
    const before = await service.get(auth, item);
    for (const readAtMs of [500, 2000]) {
      for (const overrides of [{ format: "cbr" }, { manifestHash: "c".repeat(64) }, { pageCount: 4 }, { pageKey: "c".repeat(64) }]) {
        const sibling = { ...item, bookHash: "f".repeat(64) };
        await expect(sync([sibling, { ...item, locator: { ...item.locator, ...overrides }, readAtMs }]))
          .rejects.toMatchObject({ statusCode: 422, code: "VALIDATION_FAILED" });
        expect((await service.get(auth, sibling)).items).toEqual([]);
        expect((await service.get(auth, item)).items).toEqual(before.items);
      }
    }
    const next = { ...item, locator: { ...item.locator, page: 1, pageKey: "c".repeat(64) }, readAtMs: 2000 };
    expect((await sync([next], other)).results[0]?.decision).toBe("accepted");
    expect((await sync([next], other)).results[0]?.decision).toBe("unchanged");
    expect((await sync([item])).results[0]?.decision).toBe("server_kept");
    const reread = { ...item, readAtMs: 3000 };
    expect((await sync([reread])).results[0]?.state.progress).toBe(1 / 3);
    const tied = { ...next, readAtMs: 4000 };
    await Promise.all([sync([tied]), sync([tied], other)]);
    expect((await service.get(auth, item)).items[0]?.device.deviceId).toBe([auth.deviceId, other.deviceId].sort().at(-1));
    expect((await service.get(outsider, item)).items).toEqual([]);
    await progressService.deleteBook(auth, item);
    await progressService.deleteBook(auth, item);
    expect((await service.get(other, item)).items).toEqual([]);
    expect((await sync([{ ...item, locator: { ...item.locator, manifestHash: "c".repeat(64) } }])).results[0]?.decision).toBe("accepted");
  });

  it("isolates typed formats from TXT v1, arbitrates newer rereading and deletes by exact source identity", async () => {
    const service = new DocumentProgressService(database);
    const register = async (platform: "android" | "ios") => {
      const start = await authService.startSync({ email: "documents@example.com", device: {
        deviceId: randomUUID(), deviceName: "A valid device name longer than twenty characters", platform, appVersion: "0.12.0",
      } });
      return authService.authenticate(`Bearer ${start.token}`, start.device.deviceId);
    };
    const android = await register("android"), ios = await register("ios");
    const key = { bookHash: "e".repeat(64), fileSize: 1024 };
    const time = Date.now() - 5000;
    const first = { ...key, locator: { format: "pdf" as const, version: 1 as const, page: 8, pageCount: 10, y: 0 }, readAtMs: time };
    expect((await service.sync(android, { items: [first] })).results[0]?.decision).toBe("accepted");
    expect((await progressService.list(android)).items).toHaveLength(0);
    const reread = { ...first, locator: { ...first.locator, page: 1 }, readAtMs: time + 1000 };
    expect((await service.sync(ios, { items: [reread] })).results[0]?.state.locator).toEqual(reread.locator);
    expect((await service.sync(android, { items: [first] })).results[0]?.decision).toBe("server_kept");
    expect((await service.sync(ios, { items: [reread] })).results[0]?.decision).toBe("unchanged");
    expect((await service.get(android, key)).items[0]?.device.deviceName.length).toBeGreaterThan(20);
    const other = { ...key, fileSize: 2048 };
    await service.sync(android, { items: [{ ...reread, ...other }] });
    await progressService.deleteBook(android, key);
    await progressService.deleteBook(android, key);
    expect((await service.get(ios, key)).items).toHaveLength(0);
    expect((await service.get(ios, other)).items).toHaveLength(1);
    const epub = { ...key, bookHash: "d".repeat(64), locator: { format: "epub" as const, version: 1 as const,
      resource: "OEBPS/chapter.xhtml", spineIndex: 0, spineCount: 2, textOffset: 20, textLength: 40 }, readAtMs: time };
    expect((await service.sync(android, { items: [epub] })).results[0]?.state.progress).toBe(.25);
    expect((await service.get(ios, key)).items).toHaveLength(0);
  });

  it("creates a fixed token, restores the same token, and registers a new device", async () => {
    firstStart = await authService.startSync({
      email: "reader@example.com",
      device: {
        deviceId: "10000000-0000-4000-8000-000000000000",
        deviceName: "Android One",
        platform: "android",
        appVersion: "1.0.0",
      },
    });
    secondStart = await authService.startSync({
      email: "reader@example.com",
      device: {
        deviceId: "20000000-0000-4000-8000-000000000000",
        deviceName: "iPhone",
        platform: "ios",
        appVersion: "1.0.0",
      },
    });

    expect(secondStart.token).toBe(firstStart.token);
    expect(secondStart.user.userId).toBe(firstStart.user.userId);
    const storage = await database.pool.query<{ plaintext_absent: boolean; hash_length: number }>(
      `select position(convert_to($1, 'UTF8') in token_ciphertext) = 0 as plaintext_absent,
              octet_length(token_hash)::int as hash_length
       from users where email_normalized = $2`,
      [firstStart.token, "reader@example.com"],
    );
    expect(storage.rows[0]).toEqual({ plaintext_absent: true, hash_length: 32 });
    const first = await authService.authenticate(
      `Bearer ${firstStart.token}`,
      firstStart.device.deviceId,
    );
    expect((await authService.listDevices(first)).items).toHaveLength(2);
  });

  it("performs deterministic, idempotent progress arbitration across shared-token devices", async () => {
    const first = await authService.authenticate(
      `Bearer ${firstStart.token}`,
      firstStart.device.deviceId,
    );
    const second = await authService.authenticate(
      `Bearer ${secondStart.token}`,
      secondStart.device.deviceId,
    );
    const bookHash = "d8f2b4873f0b71b6fdfca1f55f65e17100f15b06cb74cb90cdabf936c18c4f2a";

    const initial = await progressService.sync(first, {
      items: [{ bookHash, fileSize: 100, offset: 10, readAtMs: 1_000 }],
    });
    expect(initial.results[0]?.decision).toBe("accepted");
    expect(initial.results[0]?.state.version).toBe("1");
    expect((await progressService.list(second)).items).toHaveLength(1);

    const duplicate = await progressService.sync(first, {
      items: [{ bookHash, fileSize: 100, offset: 10, readAtMs: 1_000 }],
    });
    expect(duplicate.results[0]?.decision).toBe("unchanged");
    expect(duplicate.results[0]?.state.version).toBe("1");

    const tieWinner = await progressService.sync(second, {
      items: [{ bookHash, fileSize: 100, offset: 20, readAtMs: 1_000 }],
    });
    expect(tieWinner.results[0]?.decision).toBe("accepted");
    expect(tieWinner.results[0]?.state.device.deviceId).toBe(second.deviceId);
    expect(tieWinner.results[0]?.state.version).toBe("2");

    const older = await progressService.sync(first, {
      items: [{ bookHash, fileSize: 100, offset: 5, readAtMs: 999 }],
    });
    expect(older.results[0]?.decision).toBe("server_kept");
    expect((await progressService.list(first)).items).toHaveLength(1);
  });

  it("enforces device revocation, re-enables via start-sync, and isolates emails", async () => {
    const first = await authService.authenticate(
      `Bearer ${firstStart.token}`,
      firstStart.device.deviceId,
    );
    await authService.revokeDevice(first, secondStart.device.deviceId);
    await expect(
      authService.authenticate(`Bearer ${firstStart.token}`, secondStart.device.deviceId),
    ).rejects.toMatchObject({ statusCode: 403 });

    const reenabled = await authService.startSync({
      email: "reader@example.com",
      device: {
        deviceId: secondStart.device.deviceId,
        deviceName: "iPhone Restored",
        platform: "ios",
        appVersion: "1.0.1",
      },
    });
    expect(reenabled.token).toBe(firstStart.token);
    const reenabledAuth = await authService.authenticate(
      `Bearer ${reenabled.token}`,
      reenabled.device.deviceId,
    );
    expect(reenabledAuth).toMatchObject({ deviceName: "iPhone Restored" });
    expect((await progressService.list(reenabledAuth)).items).toHaveLength(1);

    const other = await authService.startSync({
      email: "other@example.com",
      device: {
        deviceId: "30000000-0000-4000-8000-000000000000",
        deviceName: "Other Phone",
        platform: "android",
        appVersion: "1.0.0",
      },
    });
    const otherAuth = await authService.authenticate(`Bearer ${other.token}`, other.device.deviceId);
    expect((await progressService.list(otherAuth)).items).toEqual([]);
    await expect(
      authService.authenticate(`Bearer ${other.token}`, firstStart.device.deviceId),
    ).rejects.toMatchObject({ statusCode: 403 });
  });

  it("converges concurrent first use of one email on one fixed token", async () => {
    const starts = await Promise.all([
      authService.startSync({
        email: "concurrent@example.com",
        device: {
          deviceId: "40000000-0000-4000-8000-000000000000",
          deviceName: "Concurrent One",
          platform: "android",
          appVersion: "1.0.0",
        },
      }),
      authService.startSync({
        email: "concurrent@example.com",
        device: {
          deviceId: "50000000-0000-4000-8000-000000000000",
          deviceName: "Concurrent Two",
          platform: "ios",
          appVersion: "1.0.0",
        },
      }),
    ]);
    expect(starts[0]?.token).toBe(starts[1]?.token);
    expect(starts[0]?.user.userId).toBe(starts[1]?.user.userId);
  });

  it("deletes only the selected book and keeps other books, identities and devices", async () => {
    const first = await authService.authenticate(`Bearer ${firstStart.token}`, firstStart.device.deviceId);
    const otherStart = await authService.startSync({
      email: "delete-isolation@example.com",
      device: { deviceId: "60000000-0000-4000-8000-000000000000", deviceName: "Other",
        platform: "ios", appVersion: "1.0.0" },
    });
    const other = await authService.authenticate(`Bearer ${otherStart.token}`, otherStart.device.deviceId);
    const book = { bookHash: "a".repeat(64), fileSize: 100 };
    const sibling = { bookHash: "a".repeat(64), fileSize: 101 };
    const differentHash = { bookHash: "b".repeat(64), fileSize: 100 };
    await progressService.sync(first, { items: [book, sibling, differentHash].map(key =>
      ({ ...key, offset: 10, readAtMs: 1000 })) });
    await progressService.sync(other, { items: [{ ...book, offset: 20, readAtMs: 1000 }] });
    const devicesBefore = (await authService.listDevices(first)).items.length;
    await progressService.deleteBook(first, book);
    await progressService.deleteBook(first, book);
    const remaining = (await progressService.list(first)).items;
    expect(remaining.some(item => item.bookHash === book.bookHash && item.fileSize === 100)).toBe(false);
    expect(remaining).toEqual(expect.arrayContaining([
      expect.objectContaining(sibling), expect.objectContaining(differentHash),
    ]));
    expect((await progressService.list(other)).items).toEqual([expect.objectContaining(book)]);
    expect((await authService.listDevices(first)).items).toHaveLength(devicesBefore);
    await expect(authService.authenticate(`Bearer ${firstStart.token}`, firstStart.device.deviceId)).resolves.toMatchObject({ userId: first.userId });
    await authService.revokeDevice(other, other.deviceId);
    await expect(progressService.deleteBook(other, book)).rejects.toMatchObject({ statusCode: 403 });
  });
  it("runs service work as a restricted role without schema creation rights", async () => {
    await expect(database.pool.query(`create table ${schema}.forbidden_ddl (id int)`))
      .rejects.toMatchObject({ code: "42501" });
  });

  it("converges concurrent uploads by reading time and UUID while retaining request order", async () => {
    const first = await newIdentity("parallel-progress");
    const second = await newIdentity("parallel-progress");
    const a = { bookHash: "c".repeat(64), fileSize: 100 };
    const b = { bookHash: "d".repeat(64), fileSize: 100 };
    const outcomes = await Promise.all([
      progressService.sync(first, { items: [{ ...b, offset: 90, readAtMs: 1000 }, { ...a, offset: 90, readAtMs: 1000 }] }),
      progressService.sync(second, { items: [{ ...a, offset: 10, readAtMs: 2000 }, { ...b, offset: 10, readAtMs: 2000 }] }),
    ]);
    expect(outcomes[0].results.map(item => item.state.bookHash)).toEqual([b.bookHash, a.bookHash]);
    expect((await progressService.list(first)).items.every(item => item.offset === 10 && item.readAtMs === 2000)).toBe(true);
    await Promise.all([first, second].map(auth => progressService.sync(auth, {
      items: [{ ...a, offset: auth === first ? 30 : 40, readAtMs: 3000 }],
    })));
    const winner = first.deviceId > second.deviceId ? first : second;
    const final = (await progressService.list(first)).items.find(item => item.bookHash === a.bookHash)!;
    expect(final.device.deviceId).toBe(winner.deviceId);
    const repeated = await progressService.sync(winner, { items: [{ ...a, offset: final.offset, readAtMs: final.readAtMs }] });
    expect(repeated.results[0]?.decision).toBe("unchanged");
    expect(repeated.results[0]?.state.version).toBe(final.version);
  });

  it("rolls back all earlier book writes if a later item violates database constraints", async () => {
    const auth = await newIdentity("rollback");
    await expect(progressService.sync(auth, { items: [
      { bookHash: "a".repeat(64), fileSize: 100, offset: 10, readAtMs: 1000 },
      { bookHash: "b".repeat(64), fileSize: 100, offset: 101, readAtMs: 1000 },
    ] })).rejects.toMatchObject({ code: "23514" });
    expect((await progressService.list(auth)).items).toEqual([]);
  });

  it("serializes concurrent capacity checks and permits updates at the limit", async () => {
    const auth = await newIdentity("capacity");
    await database.pool.query(
      `insert into reading_progress (user_id, book_hash, file_size, offset_bytes, read_at, device_id, device_uid_order)
       select $1, decode(lpad(to_hex(n), 64, '0'), 'hex'), 100, 1, to_timestamp(1), $2, $3
       from generate_series(1, 9999) n`, [auth.userId, auth.deviceDbId, auth.deviceId]);
    const results = await Promise.allSettled(["e", "f"].map(hash => progressService.sync(auth, {
      items: [{ bookHash: hash.repeat(64), fileSize: 100, offset: 2, readAtMs: 2000 }],
    })));
    expect(results.filter(result => result.status === "fulfilled")).toHaveLength(1);
    expect(results.find(result => result.status === "rejected")).toMatchObject({
      reason: { statusCode: 422, code: "PROGRESS_LIMIT_REACHED" },
    });
    expect((await progressService.list(auth)).items).toHaveLength(10000);
    const updated = await progressService.sync(auth, { items: [
      { bookHash: "1".padStart(64, "0"), fileSize: 100, offset: 3, readAtMs: 3000 },
    ] });
    expect(updated.results[0]?.decision).toBe("accepted");
  });

  it("waits for an in-flight upload transaction before deleting exactly that book", async () => {
    const auth = await newIdentity("upload-delete");
    const book = { bookHash: "a".repeat(64), fileSize: 100 };
    const client = await database.pool.connect();
    let deletion: Promise<void> | undefined;
    try {
      await client.query("begin");
      await new IdentityRepository(client).lockActiveRequester(auth);
      await new ProgressRepository(client).upsert(auth, effectiveCandidate({ ...book, offset: 25, readAtMs: 1000 }, 2000));
      deletion = progressService.deleteBook(auth, book);
      await waitForBlockedTransaction(client);
      await client.query("commit");
      await deletion;
      expect((await progressService.list(auth)).items).toEqual([]);
    } finally {
      await client.query("rollback");
      client.release();
      await deletion;
    }
  });

  it.each(["upload", "delete", "revoke"] as const)(
    "rechecks a revoked device after a queued %s obtains the identity lock", async operation => {
      const auth = await newIdentity(`revocation-${operation}`);
      const book = { bookHash: "b".repeat(64), fileSize: 100 };
      await progressService.sync(auth, { items: [{ ...book, offset: 10, readAtMs: 1000 }] });
      const client = await database.pool.connect();
      let pending: Promise<unknown> | undefined;
      try {
        await client.query("begin");
        const repository = new IdentityRepository(client);
        await repository.lockActiveRequester(auth);
        await repository.revokeDevice(auth.userId, auth.deviceId);
        const request = operation === "upload"
          ? progressService.sync(auth, { items: [{ ...book, offset: 20, readAtMs: 2000 }] })
          : operation === "delete" ? progressService.deleteBook(auth, book)
          : authService.revokeDevice(auth, auth.deviceId);
        pending = request.then(() => ({ succeeded: true }), (error: unknown) => error);
        await waitForBlockedTransaction(client);
        await client.query("commit");
        expect(await pending).toMatchObject({ statusCode: 403, code: "DEVICE_FORBIDDEN" });
        const retained = await new ProgressRepository(database.pool).select(auth.userId, book);
        expect(Number(retained.offset_bytes)).toBe(10);
      } finally {
        await client.query("rollback");
        client.release();
        await pending;
      }
    },
  );

});
