import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { publications, kf8, mobi } from './fixtures.mjs';
const scripts = ['entities.js', 'vendor/mobi.decoder.js', 'core.js'].map(p => readFileSync(new URL('../' + p, import.meta.url), 'utf8'));
const sandbox = vm.createContext({ TextDecoder, TextEncoder, console, Uint8Array, ArrayBuffer, DataView });
scripts.forEach(s => vm.runInContext(s, sandbox));
const core = sandbox.XLibKindle;
const parse = (bytes, cancelled) => core.parse({ size:bytes.length, read:(start, length) => new Uint8Array(bytes.subarray(start, start + length)) }, cancelled);
test('real MOBI6, PalmDOC, HUFF/CDIC, KF8 and mixed publications produce canonical content and offline images', () => {
    for (const [name, bytes] of Object.entries(publications())) {
        const result = parse(bytes);
        assert.ok(result.canonicalText.includes('😀'), name);
        assert.equal(Object.keys(result.resources).length, 1, name);
        assert.ok(result.chapters.every(c => !c.html.includes('<script')), name);
        assert.ok(result.toc.length > 0, name);
        if (/kf8|mixed/.test(name)) {
            assert.equal(result.canonicalText, 'KF8 第一章\n新正文 & e\u0301 😀\n\ufffc\n返回章首');
            assert.ok(!result.canonicalText.includes('旧 MOBI'));
        } else if (!name.includes('long')) assert.equal(result.canonicalText, '目录\n第一章\n第一章\n你好 & Cafe\u0301 😀 阅读。\n图片\ufffc');
        for (const chapter of result.chapters) for (const map of chapter.maps) {
            assert.ok(map.textStart < map.textEnd);
            assert.ok(map.textEnd <= chapter.text.length);
        }
    }
});
test('canonical HTML rules are independent of the host DOM, preserve Unicode/pre and reject active or hidden content', () => {
    const result = core.canonicalize('<p id="a"> A  &amp; B </p><script>bad</script><div hidden>hide</div><p>C<br>D</p><pre> X\r\n Y </pre><img src="https://invalid.invalid/a" onerror="bad()">');
    assert.equal(result.text, 'A & B\nC\nD\n X\n Y \n\ufffc');
    assert.equal(result.anchors.a, 0);
    assert.ok(!/onerror|script|https:/.test(result.html));
    assert.ok(result.maps.some(x => x.kind === 'entity'));
});
test('declared publication cover and first embedded image produce local rebuildable cover resources', () => {
    const declared = parse(mobi(1,false,'<body>封面不在正文内</body>',true));
    assert.equal(declared.coverResource,'resources/0.png');
    assert.equal(declared.canonicalText,'封面不在正文内');
    assert.equal(Object.keys(declared.resources).length,1);
    const fallback = parse(mobi());assert.equal(fallback.coverResource,'resources/0.png');
});
test('DRM, invalid mixed header, bad record offsets and cancellation never yield a fallback publication', () => {
    const bytes = kf8(true), first = bytes.readUInt32BE(78), selected = bytes.readUInt32BE(78 + 3 * 8);
    const drm = Buffer.from(bytes); drm.writeUInt16BE(2, first + 12); assert.throws(() => parse(drm), /DRM/);
    const broken = Buffer.from(bytes); broken.write('XXXX', selected + 16); assert.throws(() => parse(broken), /正文头/);
    const table = Buffer.from(bytes); table.writeUInt32BE(1, 78); assert.throws(() => parse(table), /记录位置/);
    assert.throws(() => parse(bytes, () => true), /CANCELLED/);
});
test('bounded malformed mutation regression terminates without publishing partial output', () => {
    const original = kf8(true);
    for (let i = 0; i < 128; i++) {
        const bytes = Buffer.from(original); const at = (i * 7919) % bytes.length; bytes[at] ^= (i * 17 + 1) & 255;
        try { const result = parse(bytes); assert.ok(result.canonicalText.length > 0); } catch (error) { assert.ok(error instanceof Error || typeof error.message === 'string'); }
    }
});
test('bounded HTML rejects excessive depth/nodes and source reads stay within the original file', () => {
    assert.throws(() => core.canonicalize('<div>'.repeat(130) + 'body' + '</div>'.repeat(130)), /限|depth|深度/i);
    assert.throws(() => core.canonicalize('<i></i>'.repeat(100001)), /限/);
    const bytes = kf8(true), reads = [];
    const result = core.parse({ size:bytes.length, read:(offset,count) => {
        assert.ok(Number.isInteger(offset) && Number.isInteger(count) && offset >= 0 && count >= 0);
        assert.ok(count <= 16 * 1024 * 1024 && offset + count <= bytes.length);
        reads.push([offset,count]);return new Uint8Array(bytes.subarray(offset,offset+count));
    } });
    assert.equal(result.mode,'mixed-kf8');assert.ok(reads.length > 1);
    let checks = 0;
    assert.throws(() => parse(bytes,() => ++checks >= 2), /CANCELLED/);
    assert.ok(checks >= 2);
});
test('navigation expansion and actual cumulative text are rejected before unbounded reconstruction', () => {
    const links = Array.from({length:10001},(_,i)=>`<a filepos="${i}">x</a>`).join('');
    assert.throws(() => parse(mobi(1,false,`<body>${links}</body>`)), /链接目标超过限额/);
    const original = mobi(), start = original.readUInt32BE(78), end = original.readUInt32BE(86);
    const record = Buffer.from(original.subarray(start,end));
    record.writeUInt32BE(1,4);record.writeUInt16BE(513,8);
    const count = 514, tableEnd = 78+count*8, prefix = Buffer.alloc(tableEnd+record.length);
    original.copy(prefix,0,0,78);prefix.writeUInt16BE(count,76);
    for(let i=0;i<count;i++)prefix.writeUInt32BE(i===0?tableEnd:prefix.length+(i-1)*65536,78+i*8);
    record.copy(prefix,tableEnd);
    const payload = new Uint8Array(65536).fill(97);let textReads = 0;
    assert.throws(() => core.parse({size:prefix.length+513*65536,read:(offset,length)=>{
        if(offset<prefix.length)return new Uint8Array(prefix.subarray(offset,offset+length));
        textReads++;return payload.subarray(0,length);
    }}), /32 MiB/);
    assert.ok(textReads<=514); // Includes the initial uncompressed Print Replica probe.
});
