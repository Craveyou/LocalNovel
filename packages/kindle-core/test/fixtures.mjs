// CC0-1.0: original XLib test publication, not a commercial book or DRM payload.
import { Buffer } from 'node:buffer';
import { deflateSync } from 'node:zlib';
const u16 = (b, o, n) => b.writeUInt16BE(n, o);
const u32 = (b, o, n) => b.writeUInt32BE(n, o);
const unset = 0xffffffff;
const crc32 = bytes => { let crc = 0xffffffff;for(const byte of bytes){crc ^= byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0; };
const chunk = (type,data) => {const tag=Buffer.from(type),length=Buffer.alloc(4),crc=Buffer.alloc(4);length.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([tag,data])));return Buffer.concat([length,tag,data,crc]);};
const ihdr = Buffer.alloc(13);ihdr.writeUInt32BE(1,0);ihdr.writeUInt32BE(1,4);ihdr[8]=8;ihdr[9]=6;
const png = Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(Buffer.from([0,255,255,255,255]))),chunk('IEND',Buffer.alloc(0))]);
function pdb(records) {
    const header = Buffer.alloc(78 + records.length * 8 + 2);
    header.write('XLib Kindle Fixture'); header.write('BOOKMOBI', 60); u16(header, 76, records.length);
    let offset = header.length;
    records.forEach((r, i) => { u32(header, 78 + i * 8, offset); header.writeUIntBE(i + 1, 83 + i * 8, 3); offset += r.length; });
    return Buffer.concat([header, ...records]);
}
function header({ version = 6, text, records = 1, compression = 1, resource = unset, skel = unset, frag = unset, ncx = unset, boundary, huff = unset, cover }) {
    const entries = [...(boundary == null ? [] : [[121,boundary]]),...(cover == null ? [] : [[201,cover]])];
    const exth = Buffer.alloc(12+entries.length*12);
    exth.write('EXTH'); u32(exth, 4, exth.length); u32(exth, 8, entries.length);
    entries.forEach(([tag,value],i)=>{u32(exth,12+i*12,tag);u32(exth,16+i*12,12);u32(exth,20+i*12,value);});
    const b = Buffer.alloc(264); u16(b, 0, compression); u32(b, 4, text.length); u16(b, 8, records); u16(b, 10, 4096);
    b.write('MOBI', 16); u32(b, 20, 248); u32(b, 24, 2); u32(b, 28, 65001); u32(b, 32, 0x584c4942); u32(b, 36, version);
    u32(b, 84, b.length + exth.length); u32(b, 88, 12); u32(b, 108, resource); u32(b, 112, huff); u32(b, 116, huff === unset ? 0 : 2);
    u32(b, 128, 64); u32(b, 192, unset); u32(b, 244, ncx); u32(b, 248, frag); u32(b, 252, skel); u32(b, 260, unset);
    return Buffer.concat([b, exth, Buffer.from('XLib Fixture')]);
}
const variable = n => {
    const bytes = [n & 127]; for (n >>>= 7; n; n >>>= 7) bytes.unshift(n & 127);
    bytes[bytes.length - 1] |= 128; return Buffer.from(bytes);
};
function index(tags, entries, labels = []) {
    const tagx = Buffer.alloc(12 + tags.length * 4); tagx.write('TAGX'); u32(tagx, 4, tagx.length); u32(tagx, 8, 1);
    tags.forEach(([tag, n, mask], i) => { tagx.set([tag, n, mask, 0], 12 + i * 4); });
    const main = Buffer.alloc(192); main.write('INDX'); u32(main, 4, 192); u32(main, 24, 1); u32(main, 28, 65001); u32(main, 36, entries.length); u32(main, 52, labels.length ? 1 : 0);
    const pieces = [], offsets = []; let offset = 192;
    for (const entry of entries) {
        const name = Buffer.from(entry.name), control = tags.reduce((m, row) => m | row[2], 0);
        const data = Buffer.concat([Buffer.from([name.length]), name, Buffer.from([control]), ...entry.values.map(variable)]);
        offsets.push(offset); pieces.push(data); offset += data.length;
    }
    const child = Buffer.alloc(192); child.write('INDX'); u32(child, 4, 192); u32(child, 20, offset); u32(child, 24, entries.length);
    const idxt = Buffer.alloc(4 + offsets.length * 2); idxt.write('IDXT'); offsets.forEach((v, i) => u16(idxt, 4 + i * 2, v));
    return [Buffer.concat([main, tagx]), Buffer.concat([child, ...pieces, idxt]), ...(labels.length ? [Buffer.concat(labels.map(s => { const b = Buffer.from(s); return Buffer.concat([variable(b.length), b]); }))] : [])];
}
function huffman() {
    const huff = Buffer.alloc(24 + 1024 + 256); huff.write('HUFF'); u32(huff, 8, 24); u32(huff, 12, 1048);
    for (let i = 0; i < 256; i++) u32(huff, 24 + i * 4, (255 << 8) | 128 | 8);
    const cdic = Buffer.alloc(16 + 512 + 256 * 3); cdic.write('CDIC'); u32(cdic, 4, 16); u32(cdic, 8, 256); u32(cdic, 12, 8);
    for (let i = 0; i < 256; i++) { u16(cdic, 16 + i * 2, 512 + i * 3); u16(cdic, 16 + 512 + i * 3, 0x8001); cdic[18 + 512 + i * 3] = 255 - i; }
    return [huff, cdic];
}
export function mobi(compression = 1, long = false, sourceHTML, declaredCover = false) {
    let html = sourceHTML ?? '<html><head><guide><reference type="toc" filepos="TTTTTTTTTT"/></guide></head><body><h1 id="toc">目录</h1><p><a filepos="AAAAAAAAAA">第一章</a></p><mbp:pagebreak/><h1 id="one">第一章</h1><p>你好 &amp; Cafe\u0301 😀 <b>阅读</b>。</p><p>图片<img recindex="1"/></p>' + (long ? '<p>needle 长正文。</p>'.repeat(450) : '') + '</body></html>';
    const toc = Buffer.byteLength(html.slice(0, html.indexOf('<h1 id="toc">'))), one = Buffer.byteLength(html.slice(0, html.indexOf('<h1 id="one">')));
    html = html.replace('TTTTTTTTTT', String(toc).padStart(10, '0')).replace('AAAAAAAAAA', String(one).padStart(10, '0'));
    const text = Buffer.from(html), raw = [];
    for (let offset = 0; offset < text.length; offset += 4096) {
        const bytes = text.subarray(offset, offset + 4096);
        raw.push(compression === 2 ? Buffer.concat(Array.from(bytes, b => b <= 8 || b >= 128 ? Buffer.from([1, b]) : Buffer.from([b]))) : bytes);
    }
    const dictionary = compression === 17480 ? huffman() : [], resource = 1 + raw.length + dictionary.length;
    return pdb([header({ text, records: raw.length, compression, resource, huff: dictionary.length ? 1 + raw.length : unset,cover:declaredCover ? 0 : undefined }), ...raw, ...dictionary, png]);
}
export function kf8(mixed = false) {
    const skeleton = Buffer.from('<html><body></body></html>');
    const content = Buffer.from('<h1 id="one">KF8 第一章</h1><p>新正文 &amp; e\u0301 😀</p><img src="kindle:embed:0001?mime=image/png"/><p><a href="kindle:pos:fid:0000:off:0000000000">返回章首</a></p>');
    const text = Buffer.concat([skeleton, content]);
    const skel = index([[1,1,1],[6,2,2]], [{ name:'0', values:[1,0,skeleton.length] }]);
    const frag = index([[4,1,1],[6,2,2]], [{ name:'12', values:[0,0,content.length] }]);
    const ncx = index([[1,1,1],[2,1,2],[3,1,4],[4,1,8],[6,2,16]], [{ name:'0', values:[0,content.length,0,0,0,0] }], ['KF8 第一章']);
    const base = mixed ? 3 : 0;
    const selected = header({ version:8, text, skel:2, frag:4, ncx:6, resource:9 + base });
    const records = [selected, text, ...skel, ...frag, ...ncx, png];
    if (mixed) {
        const old = Buffer.from('<html><body><p>旧 MOBI 正文，不能选中。</p></body></html>');
        records.unshift(header({ text:old, resource:12, boundary:3 }), old, Buffer.from('BOUNDARY'));
    }
    return pdb(records);
}

export const publications = () => ({
    'kindle-mobi6.mobi': mobi(), 'kindle-palmdoc.azw': mobi(2), 'kindle-huff.mobi': mobi(17480),
    'kindle-kf8.azw3': kf8(), 'kindle-mixed.mobi': kf8(true), 'kindle-long.mobi': mobi(2, true),
});
