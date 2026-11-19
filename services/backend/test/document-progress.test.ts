import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { compatibleDocumentLocators, documentLocatorSchema, documentProgress, documentSyncSchema } from "../src/document-progress.js";

const comicVectors = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/comic-locators.json", import.meta.url), "utf8")) as {
  base: Record<string, unknown>;
  validOverrides: { id: string; overrides: Record<string, unknown>; progress: number }[];
  rounding: { input: number; expected: number }[];
  invalidOverrides: { id: string; overrides: Record<string, unknown> }[];
};

describe("typed document contract", () => {
  it("uses shared Kindle bounds and rejects incompatible canonical identities", () => {
    const vectors = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/kindle-locators.json",import.meta.url),"utf8")) as typeof comicVectors;
    const base = documentLocatorSchema.parse(vectors.base);
    for (const vector of vectors.validOverrides) {
      const locator = documentLocatorSchema.parse({...vectors.base,...vector.overrides});
      expect(documentProgress(locator),vector.id).toBe(vector.progress);
    }
    for (const vector of vectors.invalidOverrides)
      expect(documentLocatorSchema.safeParse({...vectors.base,...vector.overrides}).success,vector.id).toBe(false);
    for (const key of Object.keys(vectors.base)) {
      const missing = {...vectors.base};delete missing[key];
      expect(documentLocatorSchema.safeParse(missing).success,key).toBe(false);
    }
    expect(compatibleDocumentLocators(base,documentLocatorSchema.parse({...vectors.base,textOffset:20}))).toBe(true);
    for (const overrides of [{textHash:"b".repeat(64)},{textLength:41}])
      expect(compatibleDocumentLocators(base,documentLocatorSchema.parse({...vectors.base,...overrides}))).toBe(false);
  });
  it("uses the shared CBZ/CBR locator bounds, hashes and page-level formula", () => {
    for (const vector of comicVectors.validOverrides) {
      const locator = documentLocatorSchema.parse({ ...comicVectors.base, ...vector.overrides });
      expect(documentProgress(locator), vector.id).toBe(vector.progress);
    }
    for (const vector of comicVectors.invalidOverrides)
      expect(documentLocatorSchema.safeParse({ ...comicVectors.base, ...vector.overrides }).success, vector.id).toBe(false);
    for (const field of Object.keys(comicVectors.base)) {
      const locator = { ...comicVectors.base };
      delete locator[field];
      expect(documentLocatorSchema.safeParse(locator).success, `missing ${field}`).toBe(false);
    }
    for (const y of [NaN, Infinity, -Infinity])
      expect(documentLocatorSchema.safeParse({ ...comicVectors.base, y }).success).toBe(false);
  });
  it("rounds comic y half-up at exactly six decimal places, without changing page progress", () => {
    for (const vector of comicVectors.rounding) {
      const locator = documentLocatorSchema.parse({ ...comicVectors.base, y: vector.input });
      expect(locator).toHaveProperty("y", vector.expected);
      expect(documentProgress(locator)).toBe(1 / 3);
      expect(documentLocatorSchema.parse(locator)).toEqual(locator);
    }
  });
  it("requires comic manifest identity and only compares page keys on the same page", () => {
    const base = documentLocatorSchema.parse(comicVectors.base);
    const changed = (overrides: Record<string, unknown>) => documentLocatorSchema.parse({ ...comicVectors.base, ...overrides });
    expect(compatibleDocumentLocators(base, changed({ y: 1 }))).toBe(true);
    expect(compatibleDocumentLocators(base, changed({ page: 1, pageKey: "c".repeat(64) }))).toBe(true);
    for (const overrides of [{ format: "cbr" }, { manifestHash: "c".repeat(64) }, { pageCount: 4 }, { pageKey: "c".repeat(64) }])
      expect(compatibleDocumentLocators(base, changed(overrides))).toBe(false);
    expect(compatibleDocumentLocators(base, documentLocatorSchema.parse({ format: "pdf", version: 1, page: 0, pageCount: 3, y: 0 }))).toBe(false);
  });
  it("matches Android and Swift original-file and coordinate fixtures", () => {
    const vectors = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/documents/coordinates.json", import.meta.url), "utf8")) as { file: string; bookHash: string; fileSize: number; locator: unknown; progress: number }[];
    for (const vector of vectors) {
      const bytes = readFileSync(new URL(`../../../contracts/fixtures/documents/${vector.file}`, import.meta.url));
      expect(createHash("sha256").update(bytes).digest("hex")).toBe(vector.bookHash);
      expect(bytes.length).toBe(vector.fileSize);
      expect(documentProgress(documentLocatorSchema.parse(vector.locator))).toBeCloseTo(vector.progress, 9);
    }
  });
  it("derives progress from page/content coordinates rather than binary file size", () => {
    expect(documentProgress(documentLocatorSchema.parse({ format: "pdf", version: 1, page: 2, pageCount: 4, y: .5 }))).toBe(.625);
    expect(documentProgress(documentLocatorSchema.parse({ format: "epub", version: 1, resource: "OEBPS/a.xhtml", spineIndex: 1, spineCount: 3, textOffset: 30, textLength: 60 }))).toBe(.5);
  });
  it("rejects unknown versions, invalid coordinates and unsafe package resources", () => {
    for (const locator of [
      { format: "pdf", version: 2, page: 0, pageCount: 1, y: 0 },
      { format: "pdf", version: 1, page: 1, pageCount: 1, y: 0 },
      { format: "pdf", version: 1, page: 0, pageCount: 1, y: Infinity },
      { format: "epub", version: 1, resource: "../private", spineIndex: 0, spineCount: 1, textOffset: 0, textLength: 1 },
      { format: "epub", version: 1, resource: "a.xhtml", spineIndex: 0, spineCount: 1, textOffset: 2, textLength: 1 },
    ]) expect(documentLocatorSchema.safeParse(locator).success).toBe(false);
  });
  it("rejects duplicate identities and data outside the progress contract", () => {
    const item = { bookHash: "a".repeat(64), fileSize: 100, locator: { format: "pdf", version: 1, page: 0, pageCount: 2, y: 0 }, readAtMs: 10 };
    expect(documentSyncSchema.safeParse({ items: [item] }).success).toBe(true);
    expect(documentSyncSchema.safeParse({ items: [item, item] }).success).toBe(false);
    expect(documentSyncSchema.safeParse({ items: [{ ...item, password: "must-not-be-sent" }] }).success).toBe(false);
    expect(documentSyncSchema.safeParse({ items: [{ ...item, title: "must-not-be-sent" }] }).success).toBe(false);
  });
});
