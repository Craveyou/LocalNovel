// Opt-in simulator harness. The caller owns a disposable test database and TLS certificate.
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:https";
import { request } from "node:http";
import { randomBytes, randomUUID } from "node:crypto";
import { buildApp } from "../src/app.js";

const databaseUrl = process.env.TEST_DATABASE_APP_URL;
if (!databaseUrl || !/(?:^|[_-])test(?:[_-]|$)/i.test(new URL(databaseUrl).pathname.slice(1))) {
  throw new Error("A dedicated test database is required");
}
const directory = process.env.XLIB_INTEROP_DIRECTORY;
if (!directory) throw new Error("Missing temporary harness directory");
const app = await buildApp({ nodeEnv: "test", host: "127.0.0.1", port: 0, databaseUrl,
  databaseSsl: false, dbPoolMax: 4, tokenEncryptionKey: randomBytes(32),
  enforceHttps: false, trustProxy: false, logLevel: "silent" });
await app.listen({ host: "127.0.0.1", port: 0 });
const address = app.server.address();
if (!address || typeof address === "string") throw new Error("Missing backend port");
const tls = createServer({ key: await readFile(`${directory}/key.pem`), cert: await readFile(`${directory}/cert.pem`) }, (incoming, outgoing) => {
  const proxy = request({ hostname: "127.0.0.1", port: address.port, path: incoming.url ?? "/",
    method: incoming.method ?? "GET", headers: incoming.headers }, response => {
    outgoing.writeHead(response.statusCode ?? 500, response.headers); response.pipe(outgoing);
  });
  proxy.on("error", () => { outgoing.writeHead(502); outgoing.end(); });
  incoming.pipe(proxy);
});
await new Promise<void>(resolve => tls.listen(0, "127.0.0.1", resolve));
const publicAddress = tls.address();
if (!publicAddress || typeof publicAddress === "string") throw new Error("Missing TLS port");
await writeFile(`${directory}/connection.json`, JSON.stringify({ url: `https://localhost:${publicAddress.port}`,
  certificate: (await readFile(`${directory}/cert.der`)).toString("base64"), run: randomUUID() }));
process.stdout.write("Disposable PostgreSQL + HTTPS mobile test server ready\n");
let closing = false;
const close = async () => { if (closing) return; closing = true; tls.close(); await app.close(); process.exit(0); };
process.on("SIGTERM", () => { void close(); }); process.on("SIGINT", () => { void close(); });
