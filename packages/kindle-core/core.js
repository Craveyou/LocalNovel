/* XLib offline Kindle core. The same bytes run in JavaScriptCore and Node/WebView.
 * Hosts supply bounded random reads and cancellation, never paths or network APIs.
 * Parsing results are preparation data, not business persistence.
 */
(function () {
'use strict';
const MAX_TEXT = 32 * 1024 * 1024, MAX_RECORD = 16 * 1024 * 1024;
const UNSET = 0xffffffff;
const fail = message => { throw new Error(message); };
let steps = 0, cancelled = () => false;
globalThis.xlibStep = () => {
    if (++steps > 10000000) fail('Kindle 解析超过复杂度限额');
    if ((steps & 255) === 0 && cancelled()) fail('CANCELLED');
};
const utf8 = value => new TextEncoder().encode(value);
const ascii = value => {
    // Keep byte indexes without allocating one JS array entry per source byte.
    const chunks = [];
    for (let i = 0; i < value.length; i += 8192) {
        globalThis.xlibStep();chunks.push(String.fromCharCode(...value.subarray(i,i+8192)));
    }
    return chunks.join('');
};
const uint = (bytes, offset, size = 4) => {
    globalThis.xlibStep();
    if (offset < 0 || offset + size > bytes.length) fail('Kindle 记录被截断');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return size === 2 ? view.getUint16(offset) : view.getUint32(offset);
};
const concat = arrays => {
    const size = arrays.reduce((sum, x) => sum + x.length, 0);
    if (size > MAX_TEXT) fail('Kindle 正文超过 32 MiB 限额');
    const result = new Uint8Array(size);
    let offset = 0;
    for (const bytes of arrays) { result.set(bytes, offset); offset += bytes.length; }
    return result;
};
const escape = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function inspect(source) {
    if (!Number.isSafeInteger(source.size) || source.size < 94 || source.size > 1024 * 1024 * 1024) fail('Kindle 文件大小无效或超过 1 GiB');
    const read = (start, length) => {
        if (cancelled()) fail('CANCELLED');
        if (!Number.isSafeInteger(start) || !Number.isSafeInteger(length) || start < 0 || length < 0 || start + length > source.size || length > MAX_RECORD) fail('Kindle 读取范围无效');
        const value = source.read(start, length);
        if (!(value instanceof Uint8Array) || value.length !== length) fail('Kindle 原文件读取不完整');
        return value;
    };
    const pdb = read(0, 78);
    if (ascii(pdb.subarray(60, 68)) !== 'BOOKMOBI') fail('不是支持的 Kindle 容器');
    if (uint(pdb, 72) !== 0) fail('暂不支持多记录表 Kindle 文件');
    const count = uint(pdb, 76, 2), tableEnd = 78 + count * 8;
    if (count < 2 || tableEnd > source.size) fail('Kindle 记录表无效');
    const table = read(78, count * 8), offsets = [];
    for (let i = 0; i < count; i++) {
        const offset = uint(table, i * 8);
        if (offset < tableEnd || offset > source.size || i > 0 && offset < offsets[i - 1]) fail('Kindle 记录位置无效');
        offsets.push(offset);
    }
    offsets.push(source.size);
    const record = index => {
        if (!Number.isInteger(index) || index < 0 || index >= count) fail('Kindle 记录索引越界');
        return read(offsets[index], offsets[index + 1] - offsets[index]);
    };
    function header(index) {
        const bytes = record(index);
        if (bytes.length < 132 || bytes.length > 1024 * 1024 || ascii(bytes.subarray(16, 20)) !== 'MOBI') fail('Kindle 正文头无效');
        const length = uint(bytes, 20), version = uint(bytes, 36), encoding = uint(bytes, 28);
        if (length < 116 || length + 16 > bytes.length) fail('Kindle 正文头越界');
        if (![6, 7, 8].includes(version)) fail('不支持此 MOBI 版本');
        if (![1252, 65001].includes(encoding)) fail('不支持此 Kindle 正文编码');
        if (version === 8 && length < 248) fail('KF8 正文头不完整');
        if (uint(bytes, 12, 2) !== 0 || length >= 168 && (uint(bytes, 172) || uint(bytes, 176) || uint(bytes, 180) & 1)) fail('不支持带 DRM 的 Kindle 电子书');
        const compression = uint(bytes, 0, 2), textLength = uint(bytes, 4), textRecords = uint(bytes, 8, 2);
        if (![1, 2, 17480].includes(compression)) fail('不支持此 Kindle 压缩方式');
        if (!textLength || textLength > MAX_TEXT || !textRecords || index + textRecords >= count) fail('Kindle 正文记录或展开大小无效');
        for (let i = index + 1; i <= index + textRecords; i++) if (offsets[i + 1] <= offsets[i]) fail('Kindle 正文记录为空');
        let boundary = UNSET;
        if (uint(bytes, 128) & 64) {
            const start = 16 + length;
            if (ascii(bytes.subarray(start, start + 4)) !== 'EXTH') fail('Kindle EXTH 标记无效');
            const size = uint(bytes, start + 4), n = uint(bytes, start + 8);
            if (size < 12 || start + size > bytes.length || n > 1024 || n * 8 > size - 12) fail('Kindle EXTH 记录表无效');
            let cursor = start + 12, seen = false;
            for (let i = 0; i < n; i++) {
                const tag = uint(bytes, cursor), size = uint(bytes, cursor + 4);
                if (size < 8 || cursor + size > start + uint(bytes, start + 4)) fail('Kindle EXTH 记录越界');
                if (tag === 121) {
                    if (seen || size !== 12) fail('混合格式边界重复或无效');
                    seen = true; boundary = uint(bytes, cursor + 8);
                }
                if (tag === 122 && !['', 'false', 'no', '0'].includes(ascii(bytes.subarray(cursor + 8, cursor + size)).trim().toLowerCase())) fail('暂不支持固定版式 Kindle 电子书');
                cursor += size;
            }
        }
        if (compression === 1 && ascii(record(index + 1).subarray(0, 4)) === '%MOP') fail('暂不支持 Print Replica Kindle 电子书');
        return { index, version, textLength, textRecords, boundary };
    }
    const first = header(0);
    let chosen = first, mode = first.version === 8 ? 'kf8' : 'mobi6';
    if (first.boundary !== UNSET) {
        const index = first.boundary;
        if (first.version === 8 || index < 2 || index >= count - 1 || first.textRecords >= index - 1 || ascii(record(index - 1).subarray(0, 8)) !== 'BOUNDARY') fail('混合格式边界无效');
        chosen = header(index);
        if (chosen.version !== 8 || chosen.boundary !== UNSET) fail('混合格式 KF8 头无效，不能退回 MOBI 正文');
        mode = 'mixed-kf8';
    }
    // Adapter preserves random reads instead of retaining a full-file ArrayBuffer.
    const file = { slice(start = 0, end = source.size) { return { arrayBuffer: () => read(start, end - start).slice().buffer }; } };
    const resourceStart = uint(record(0), 108);
    return { file, chosen, mode, record, resourceRange(index) {
        const absolute = resourceStart + index;
        if (!Number.isInteger(absolute) || absolute < 0 || absolute >= count) fail('Kindle 图片记录越界');
        return { offset: offsets[absolute], size: offsets[absolute + 1] - offsets[absolute] };
    } };
}

function parseTree(html) {
    if (html.length > MAX_TEXT) fail('Kindle 内容单元超过限额');
    const root = { name: 'root', attrs: {}, children: [] }, stack = [root];
    const voids = new Set(['area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr','pagebreak','mbp:pagebreak']);
    let cursor = 0, count = 0;
    while (cursor < html.length) {
        globalThis.xlibStep();
        if (++count > 200000 || stack.length > 128) fail('Kindle HTML 结构超过限额');
        const start = cursor;
        if (html[cursor] !== '<') {
            const next = html.indexOf('<', cursor);
            cursor = next < 0 ? html.length : next;
            stack.at(-1).children.push({ name: '#text', value: html.slice(start, cursor), start, end: cursor });
            continue;
        }
        if (html.startsWith('<!--', cursor)) { const end = html.indexOf('-->', cursor + 4); if (end < 0) fail('Kindle HTML 注释不完整'); cursor = end + 3; continue; }
        let quote = null; cursor++;
        for (; cursor < html.length; cursor++) {
            const c = html[cursor];
            if (quote) { if (c === quote) quote = null; }
            else if (c === '"' || c === "'") quote = c;
            else if (c === '>') break;
        }
        if (cursor === html.length) fail('Kindle HTML 标签不完整');
        const token = html.slice(start + 1, cursor++), match = token.match(/^\s*(\/?)\s*([a-z][\w:-]*)/i);
        if (!match) continue;
        const name = match[2].toLowerCase();
        if (match[1]) {
            const at = stack.findLastIndex(node => node.name === name);
            if (at > 0) stack.length = at;
            continue;
        }
        if (['p','li','tr','td','th'].includes(name) && stack.at(-1).name === name) stack.pop();
        const attrs = {};
        const pattern = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
        const remainder = token.slice(match[0].length);
        for (const attribute of remainder.matchAll(pattern)) {
            const key = attribute[1].toLowerCase();
            if (!(key in attrs)) attrs[key] = globalThis.XLibKindleEntities(attribute[2] ?? attribute[3] ?? attribute[4] ?? '');
        }
        const node = { name, attrs, children: [], start, end: cursor };
        stack.at(-1).children.push(node);
        if (!voids.has(name) && !/\/\s*$/.test(token)) stack.push(node);
    }
    return root;
}

// Canonicalization is intentionally independent of browser HTML repair/innerText.
function canonicalize(html, resource = () => null) {
    const tree = parseTree(html), anchors = {}, links = [], maps = [], parts = [];
    let text = '', pendingBreak = false, pendingSpace = null, renderedSize = 0;
    const skip = new Set(['head','script','style','iframe','object','embed','form','input','button','audio','video','noscript','template','svg','math']);
    const blocks = new Set(['p','div','section','article','header','footer','main','nav','aside','h1','h2','h3','h4','h5','h6','li','ul','ol','blockquote','pre','table','tr','hr']);
    function emit(value, start, end, kind = 'text', markup) {
        if (!value) return;
        globalThis.xlibStep();
        if (maps.length >= 200000) fail('Kindle 文本映射超过限额');
        const offset = text.length;
        text += value;
        if (text.length > MAX_TEXT) fail('Kindle 规范正文超过限额');
        maps.push({ textStart: offset, textEnd: text.length, sourceStart: start, sourceEnd: end, kind });
        const rendered = markup ?? escape(value);
        renderedSize += rendered.length;
        if (renderedSize > MAX_TEXT * 2) fail('Kindle 显示正文超过限额');
        parts.push(rendered);
    }
    function flush() {
        if (pendingBreak) { if (text && !text.endsWith('\n')) emit('\n', -1, -1, 'separator'); pendingBreak = false; pendingSpace = null; }
        else if (pendingSpace) { if (text && !/\s$/.test(text)) emit(' ', ...pendingSpace, 'space'); pendingSpace = null; }
    }
    function walk(node, pre = false, link = null) {
        globalThis.xlibStep();
        if (node.name === '#text') {
            const pattern = /&(?:#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);|[^&]+|&/gi;
            let markupStart = parts.length;
            for (const token of node.value.matchAll(pattern)) {
                const value = globalThis.XLibKindleEntities(token[0]).replace(/\r\n?/g, '\n');
                const start = node.start + token.index, end = start + token[0].length;
                if (pre) { flush(); emit(value, start, end, value === token[0] ? 'text' : 'entity'); continue; }
                for (const piece of value.matchAll(/[\t\n\f\r ]+|[^\t\n\f\r ]+/g)) {
                    const same = value === token[0], from = same ? start + piece.index : start, to = same ? from + piece[0].length : end;
                    if (/^[\t\n\f\r ]+$/.test(piece[0])) pendingSpace = [pendingSpace?.[0] ?? from, to];
                    else { flush(); emit(piece[0], from, to, same ? 'text' : 'entity'); }
                }
            }
            if (link && parts.length > markupStart) {
                const content = parts.splice(markupStart).join('');
                const prefix = `<a href="${escape(link)}">`;
                renderedSize += prefix.length + 4;
                if (renderedSize > MAX_TEXT * 2) fail('Kindle 显示正文超过限额');
                parts.push(`${prefix}${content}</a>`);
            }
            return;
        }
        if (skip.has(node.name) || 'hidden' in node.attrs || /(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.test(node.attrs.style ?? '')) return;
        const block = blocks.has(node.name);
        if (block || node.name === 'br') { pendingBreak = true; pendingSpace = null; }
        if (node.attrs.id || node.attrs.name || node.attrs.aid) {
            flush();
            for (const id of [node.attrs.id, node.attrs.name, node.attrs.aid].filter(Boolean)) if (!(id in anchors)) anchors[id] = text.length;
        }
        if (node.name === 'img') {
            flush(); const path = resource(node.attrs);
            emit('\ufffc', node.start, node.end, 'image', `${path ? `<img src="/${escape(path)}" alt="${escape(node.attrs.alt ?? '')}">` : ''}<span style="font-size:0!important" aria-hidden="true">\ufffc</span>`);
        }
        let href = link;
        if (node.name === 'a') {
            href = node.attrs.filepos ? `filepos:${node.attrs.filepos}` : node.attrs.href;
            if (href?.length > 4096) fail('Kindle 链接超过限额');
            if (href) { links.push({ href, label: node.children.filter(c => c.name === '#text').map(c => globalThis.XLibKindleEntities(c.value)).join('').trim() }); }
            if (href && !/^(?:filepos:|kindle:pos:|#|https?:)/i.test(href)) href = null;
        }
        for (const child of node.children) walk(child, pre || node.name === 'pre', href);
        if (block) { pendingBreak = true; pendingSpace = null; }
    }
    walk(tree);
    return { text, html: `<div style="white-space:pre-wrap">${parts.join('')}</div>`, anchors, maps, links };
}

function parse(source, isCancelled = () => false) {
    steps = 0; cancelled = isCancelled;
    const input = inspect(source), mobi = new globalThis.XLibMOBI.MOBI({ unzlib: () => fail('不加载压缩内置字体') });
    mobi.open(input.file);
    const decoded = []; let decodedSize = 0;
    for (let i = 0; i < input.chosen.textRecords; i++) {
        globalThis.xlibStep();
        const data = mobi.loadText(i);
        if (data.length > 65536) fail('Kindle 单条正文记录超过限额');
        decodedSize += data.length;
        if (decodedSize > MAX_TEXT) fail('Kindle 正文超过 32 MiB 限额');
        decoded.push(data);
    }
    const raw = concat(decoded);
    if (raw.length < input.chosen.textLength) fail('Kindle 展开正文被截断');
    const content = raw.subarray(0, input.chosen.textLength), units = [];
    let ncx = [];
    if (mobi.headers.mobi.indx < UNSET) ncx = mobi.getNCX() ?? [];
    const navigation = [], pending = [...ncx].reverse();
    while (pending.length) {
        globalThis.xlibStep();
        if (navigation.length >= 10000) fail('Kindle 导航项超过限额');
        const item = pending.pop();navigation.push(item);
        if (item.children) pending.push(...[...item.children].reverse());
    }
    const positions = new Map(navigation.filter(x => x.pos).map(x => [x.pos.join(':'), x]));
    for (const match of ascii(content).matchAll(/kindle:pos:fid:([0-9a-v]+):off:([0-9a-v]+)/gi)) {
        globalThis.xlibStep();
        const pos = [parseInt(match[1], 32), parseInt(match[2], 32)];
        if (!positions.has(pos.join(':'))) positions.set(pos.join(':'), { pos });
        if (positions.size > 10000) fail('Kindle 链接目标超过限额');
    }
    if (input.chosen.version < 8) {
        const bytes = ascii(content), targets = new Set();
        for (const match of bytes.matchAll(/\bfilepos\s*=\s*['"]?(\d+)/gi)) {
            globalThis.xlibStep();targets.add(Number(match[1]));
            if (targets.size > 10000) fail('Kindle 链接目标超过限额');
        }
        for (const item of navigation) if (Number.isInteger(item.offset)) targets.add(item.offset);
        if (targets.size > 10000) fail('Kindle 链接目标超过限额');
        const starts = [0];
        for (const match of bytes.matchAll(/<\s*(?:mbp:)?pagebreak\b[^>]*>/gi)) {
            globalThis.xlibStep();if (match.index > starts.at(-1)) starts.push(match.index);
            if (starts.length > 10000) fail('Kindle 正文单元超过限额');
        }
        const orderedTargets = [...targets].filter(x => Number.isSafeInteger(x) && x >= 0 && x < content.length).sort((a,b)=>a-b);
        let targetIndex = 0;
        for (let i = 0; i < starts.length; i++) {
            globalThis.xlibStep();
            const start = starts[i], end = starts[i + 1] ?? content.length, chunks = [];
            let cursor = start;
            while (targetIndex < orderedTargets.length && orderedTargets[targetIndex] < end) {
                const offset = orderedTargets[targetIndex++];
                chunks.push(content.subarray(cursor, offset), utf8(`<a id="filepos${offset}"></a>`)); cursor = offset;
            }
            chunks.push(content.subarray(cursor, end));
            units.push(mobi.decode(concat(chunks)).replace(/<\s*(?:mbp:)?pagebreak\b[^>]*>/gi, ''));
        }
    } else {
        const load = mobi.loadRecord.bind(mobi), { kf8 } = mobi.headers;
        const skels = globalThis.XLibMOBI.getIndexData(kf8.skel, load).table;
        const fragments = globalThis.XLibMOBI.getIndexData(kf8.frag, load).table;
        if (!skels.length || skels.length > 10000) fail('KF8 正文单元数量无效');
        let fragStart = 0, reconstructedBytes = 0;
        for (const skel of skels) {
            globalThis.xlibStep();
            const count = skel.tagMap[1]?.[0], [offset, length] = skel.tagMap[6] ?? [];
            if (!Number.isInteger(count) || count < 0 || fragStart + count > fragments.length || !Number.isInteger(offset) || !Number.isInteger(length) || offset + length > content.length) fail('KF8 骨架索引无效');
            let bytes = content.slice(offset, offset + length);
            for (const frag of fragments.slice(fragStart, fragStart + count)) {
                globalThis.xlibStep();
                const insert = Number(frag.name) - offset, [from, size] = frag.tagMap[6] ?? [];
                if (!Number.isInteger(insert) || insert < 0 || insert > bytes.length || !Number.isInteger(from) || !Number.isInteger(size) || from < 0 || size < 0 || offset + length + from + size > content.length) fail('KF8 片段索引无效');
                reconstructedBytes += bytes.length + size;
                if (reconstructedBytes > 128 * 1024 * 1024) fail('KF8 片段重建超过复制预算');
                bytes = concat([bytes.subarray(0, insert), content.subarray(offset + length + from, offset + length + from + size), bytes.subarray(insert)]);
            }
            // Resolve Kindle fragment links to original element IDs before sanitizing.
            let html = mobi.decode(bytes);
            const chapterFragments = fragments.slice(fragStart, fragStart + count);
            for (const target of positions.values()) {
                if (!target.pos) continue;
                const [fid, off] = target.pos, frag = chapterFragments.find(f => f.tagMap[4]?.[0] === fid);
                if (!frag) continue;
                const [from, size] = frag.tagMap[6];
                if (off < 0 || off >= size) continue;
                const following = mobi.decode(content.subarray(offset + length + from + off, offset + length + from + size));
                const id = following.match(/^\s*<[^>]*\b(?:id|name|aid)\s*=\s*['"]([^'"]+)['"]/i)?.[1];
                if (id) target.anchor = id, target.unit = units.length;
            }
            units.push(html); fragStart += count;
        }
        if (fragStart !== fragments.length) fail('KF8 存在未归属的正文片段');
    }
    if (!units.length || units.length > 10000) fail('Kindle 没有可阅读正文或单元过多');
    const resources = {}, bytesByResource = new Map();
    const image = attrs => {
        const uri = attrs.src ?? '', embed = uri.match(/^kindle:embed:(\w+)/i);
        if (!attrs.recindex && !embed) return null;
        const index = attrs.recindex ? Number(attrs.recindex) - 1 : parseInt(embed[1], 32) - 1;
        if (!Number.isInteger(index) || index < 0) fail('Kindle 图片索引无效');
        if (bytesByResource.has(index)) return bytesByResource.get(index);
        const bytes = new Uint8Array(mobi.loadResource(index));
        let ext;
        if (bytes[0] === 0xff && bytes[1] === 0xd8) ext = 'jpg';
        else if (ascii(bytes.subarray(0, 8)) === '\x89PNG\r\n\x1a\n') ext = 'png';
        else if (/^GIF8[79]a$/.test(ascii(bytes.subarray(0, 6)))) ext = 'gif';
        else fail('Kindle 图片损坏或格式不支持');
        const path = `resources/${index}.${ext}`;
        resources[path] = { index, ...input.resourceRange(index) }; bytesByResource.set(index, path); return path;
    };
    let total = 0, mappings = 0;
    const chapters = units.map((html, index) => {
        const value = canonicalize(html, image), start = total;
        mappings += value.maps.length;
        if (mappings > 500000) fail('Kindle 全书映射超过限额');
        if (index) total++;
        const textStart = total; total += value.text.length;
        return { ...value, resource: `units/${index}.html`, textStart, sourceHTML: html };
    });
    const canonicalText = chapters.map(c => c.text).join('\n');
    if (!canonicalText.length || canonicalText.length > MAX_TEXT) fail('Kindle 没有有效规范正文或超过限额');
    const exth = mobi.headers.exth, coverIndex = exth?.coverOffset < UNSET ? exth.coverOffset : exth?.thumbnailOffset < UNSET ? exth.thumbnailOffset : null;
    const coverResource = coverIndex == null ? Object.keys(resources)[0] ?? null : image({recindex:String(coverIndex+1)});
    const targets = {};
    chapters.forEach((chapter, unit) => { for (const [id, offset] of Object.entries(chapter.anchors)) targets[id] ??= { unit, offset }; });
    const toc = navigation.flatMap(item => {
        const target = input.chosen.version < 8 ? targets[`filepos${item.offset}`] : item.anchor ? { unit: item.unit, offset: chapters[item.unit].anchors[item.anchor] } : null;
        return target && item.label ? [{ title: globalThis.XLibKindleEntities(item.label), ...target }] : [];
    });
    if (!toc.length && input.chosen.version < 8) {
        const guide = units.join('').match(/<reference\b[^>]*\btype\s*=\s*['"]toc['"][^>]*\bfilepos\s*=\s*['"]?(\d+)/i);
        const chapter = guide && chapters.find(c => `filepos${Number(guide[1])}` in c.anchors);
        if (chapter) for (const item of chapter.links) {
            const target = targets[`filepos${Number(item.href.replace(/^filepos:/, ''))}`];
            if (target && item.label) toc.push({ title: item.label, ...target });
        }
    }
    for (const chapter of chapters) chapter.html = chapter.html.replace(/href="(?:filepos:)(\d+)"/g, (all, id) => {
        const target = targets[`filepos${Number(id)}`];
        return target ? `href="xlib-book://book.xlib.invalid/units/${target.unit}.html#filepos${Number(id)}"` : 'href="xlib-unsupported:anchor"';
    });
    for (const chapter of chapters) chapter.html = chapter.html.replace(/href="kindle:pos:fid:([0-9a-v]+):off:([0-9a-v]+)"/gi, (all, fid, off) => {
        const target = positions.get(`${parseInt(fid, 32)}:${parseInt(off, 32)}`);
        if (!target?.anchor || !(target.anchor in chapters[target.unit].anchors)) return 'href="xlib-unsupported:anchor"';
        return `href="xlib-book://book.xlib.invalid/units/${target.unit}.html#${encodeURIComponent(target.anchor)}"`;
    });
    return { coreVersion: 1, profile: 'kindle-text-v1', mode: input.mode, canonicalText, chapters, toc, resources, coverResource, metadata: mobi.getMetadata() };
}
globalThis.XLibKindle = { parse, inspect, canonicalize };
})();
