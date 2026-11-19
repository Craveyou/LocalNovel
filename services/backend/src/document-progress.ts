import { z } from "zod";
import type { AuthContext } from "./auth-service.js";
import { Database } from "./database.js";
import { ApiError } from "./errors.js";
import { IdentityRepository } from "./identity-repository.js";
import { MAX_TIMESTAMP_MS, type ProgressBookKey } from "./schemas.js";

const integer = z.number().int().safe().nonnegative();
const resource = z.string().min(1).max(1024).refine(value =>
  !/[\\:%#?]/.test(value) && !Array.from(value).some(c => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127
    || (c.length === 1 && c.charCodeAt(0) >= 0xd800 && c.charCodeAt(0) <= 0xdfff)) &&
  value.split("/").every(part => part !== "" && part !== "." && part !== ".."), "invalid resource path");
const pdf = z.object({
  format: z.literal("pdf"), version: z.literal(1), page: integer,
  pageCount: z.number().int().min(1).max(100_000),
  y: z.number().finite().min(0).max(1).transform(value => Math.round(value * 1e6) / 1e6),
}).strict().refine(value => value.page < value.pageCount, "page out of range");
const epub = z.object({
  format: z.literal("epub"), version: z.literal(1), resource,
  spineIndex: integer, spineCount: z.number().int().min(1).max(10_000),
  textOffset: integer.max(2147483647), textLength: integer.max(2147483647),
}).strict().refine(value => value.spineIndex < value.spineCount && value.textOffset <= value.textLength,
  "content position out of range");
// Use decimal arithmetic so binary multiplication cannot move an exact half
// tie (such as 0.5000005) below the six-decimal rounding boundary.
function comicY(value: number): number {
  const [mantissa, exponent = "0"] = value.toString().split("e");
  const [whole, fraction = ""] = mantissa!.split(".");
  const digits = BigInt(whole! + fraction);
  const scale = 6 + Number(exponent) - fraction.length;
  if (scale >= 0) return Number(digits * 10n ** BigInt(scale)) / 1e6;
  const divisor = 10n ** BigInt(-scale);
  return Number((digits * 2n + divisor) / (divisor * 2n)) / 1e6;
}
const comic = z.object({
  format: z.enum(["cbz", "cbr"]), version: z.literal(1), profile: z.literal("comic-order-v1"),
  manifestHash: z.string().regex(/^[0-9a-f]{64}$/), pageKey: z.string().regex(/^[0-9a-f]{64}$/),
  page: integer, pageCount: z.number().int().min(1).max(10_000),
  y: z.number().finite().min(0).max(1).transform(comicY),
}).strict().refine(value => value.page < value.pageCount, "page out of range");
const kindle = z.object({
  format: z.literal("kindle"), version: z.literal(1), profile: z.literal("kindle-text-v1"),
  textHash: z.string().regex(/^[0-9a-f]{64}$/), textOffset: integer.max(2147483647),
  textLength: z.number().int().min(1).max(2147483647),
}).strict().refine(value => value.textOffset <= value.textLength, "content position out of range");
export const documentLocatorSchema = z.union([pdf, epub, comic, kindle]);
export type DocumentLocator = z.infer<typeof documentLocatorSchema>;
export const documentSyncSchema = z.object({ items: z.array(z.object({
  bookHash: z.string().regex(/^[0-9a-f]{64}$/), fileSize: z.number().int().safe().positive(),
  locator: documentLocatorSchema, readAtMs: integer.max(MAX_TIMESTAMP_MS),
}).strict()).min(1).max(100) }).strict().superRefine((value, context) => {
  const keys = new Set<string>();
  value.items.forEach((item, index) => {
    const key = `${item.bookHash}:${item.fileSize}`;
    if (keys.has(key)) context.addIssue({ code: "custom", path: ["items", index], message: "duplicate bookKey" });
    keys.add(key);
  });
});
type DocumentInput = z.infer<typeof documentSyncSchema>;
interface Row {
  book_hash: string; file_size: string; locator: DocumentLocator; read_at: Date; version: string;
  device_id: string; device_uid: string; device_name: string; platform: "ios" | "android";
}
export function documentProgress(locator: DocumentLocator): number {
  if (locator.format === "kindle") return locator.textOffset / locator.textLength;
  if (locator.format === "pdf") return (locator.page + locator.y) / locator.pageCount;
  if (locator.format === "epub")
    return (locator.spineIndex + (locator.textLength ? locator.textOffset / locator.textLength : 0)) / locator.spineCount;
  return (locator.page + 1) / locator.pageCount;
}
export function compatibleDocumentLocators(previous: DocumentLocator, incoming: DocumentLocator): boolean {
  if (previous.format !== incoming.format || previous.version !== incoming.version) return false;
  if (previous.format === "kindle") return incoming.format === "kindle"
    && previous.profile === incoming.profile && previous.textHash === incoming.textHash && previous.textLength === incoming.textLength;
  if (previous.format === "cbz" || previous.format === "cbr") {
    if (incoming.format !== "cbz" && incoming.format !== "cbr") return false;
    return previous.profile === incoming.profile && previous.manifestHash === incoming.manifestHash
      && previous.pageCount === incoming.pageCount
      && (previous.page !== incoming.page || previous.pageKey === incoming.pageKey);
  }
  return true;
}
function state(row: Row) {
  const locator = documentLocatorSchema.parse(row.locator);
  return { bookHash: row.book_hash, fileSize: Number(row.file_size), locator, progress: documentProgress(locator),
    readAtMs: row.read_at.getTime(), version: row.version,
    device: { deviceId: row.device_uid, deviceName: row.device_name, platform: row.platform } };
}
const select = `select encode(p.book_hash,'hex') as book_hash,p.file_size,p.locator,p.read_at,p.version,p.device_id,
  d.device_uid,d.device_name,d.platform from document_progress p join devices d on d.id=p.device_id
  where p.user_id=$1 and p.book_hash=decode($2,'hex') and p.file_size=$3`;

export class DocumentProgressService {
  constructor(private readonly database: Database) {}
  async get(auth: AuthContext, book: ProgressBookKey) {
    const rows = await this.database.pool.query<Row>(select, [auth.userId, book.bookHash, String(book.fileSize)]);
    return { serverTimeMs: Date.now(), items: rows.rows.map(state) };
  }
  async sync(auth: AuthContext, input: DocumentInput) {
    const now = Date.now();
    return this.database.transaction(async client => {
      await new IdentityRepository(client).lockActiveRequester(auth);
      const count = await client.query<{ count: string }>(`select
        (select count(*) from reading_progress where user_id=$1) +
        (select count(*) from document_progress where user_id=$1) as count`, [auth.userId]);
      let total = Number(count.rows[0]?.count ?? 0);
      const results = [];
      for (const item of input.items) {
        const previous = (await client.query<Row>(select, [auth.userId, item.bookHash, String(item.fileSize)])).rows[0];
        if (!previous && ++total > 10_000) throw new ApiError(422, "PROGRESS_LIMIT_REACHED", "progress limit reached");
        if (previous && !compatibleDocumentLocators(documentLocatorSchema.parse(previous.locator), item.locator))
          throw new ApiError(422, "VALIDATION_FAILED", "incompatible document locator");
        const adjusted = item.readAtMs > now + 5 * 60_000;
        const time = adjusted ? now : item.readAtMs;
        const accepted = !previous || time > previous.read_at.getTime() ||
          (time === previous.read_at.getTime() && auth.deviceId > previous.device_uid);
        if (accepted) await client.query(`insert into document_progress
          (user_id,book_hash,file_size,locator,read_at,device_id,device_uid_order) values($1,decode($2,'hex'),$3,$4,$5,$6,$7)
          on conflict(user_id,book_hash,file_size) do update set locator=excluded.locator,read_at=excluded.read_at,
          device_id=excluded.device_id,device_uid_order=excluded.device_uid_order,version=document_progress.version+1`,
        [auth.userId, item.bookHash, String(item.fileSize), item.locator, new Date(time), auth.deviceDbId, auth.deviceId]);
        const finalRow = (await client.query<Row>(select, [auth.userId, item.bookHash, String(item.fileSize)])).rows[0]!;
        const unchanged = !accepted && previous?.device_uid === auth.deviceId && time === previous.read_at.getTime()
          && JSON.stringify(documentLocatorSchema.parse(previous.locator)) === JSON.stringify(item.locator);
        results.push({ decision: accepted ? "accepted" : unchanged ? "unchanged" : "server_kept",
          timeAdjusted: adjusted, state: state(finalRow) });
      }
      return { serverTimeMs: now, results };
    });
  }
}
