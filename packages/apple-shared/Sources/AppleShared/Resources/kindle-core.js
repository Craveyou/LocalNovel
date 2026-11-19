// Generated from packages/kindle-core; run node packages/kindle-core/build.mjs.
(function(){
'use strict';
const entities = {"AElig":"Æ","Aacute":"Á","Acirc":"Â","Agrave":"À","Alpha":"Α","Aring":"Å","Atilde":"Ã","Auml":"Ä","Beta":"Β","Ccedil":"Ç","Chi":"Χ","Dagger":"‡","Delta":"Δ","ETH":"Ð","Eacute":"É","Ecirc":"Ê","Egrave":"È","Epsilon":"Ε","Eta":"Η","Euml":"Ë","Gamma":"Γ","Iacute":"Í","Icirc":"Î","Igrave":"Ì","Iota":"Ι","Iuml":"Ï","Kappa":"Κ","Lambda":"Λ","Mu":"Μ","Ntilde":"Ñ","Nu":"Ν","OElig":"Œ","Oacute":"Ó","Ocirc":"Ô","Ograve":"Ò","Omega":"Ω","Omicron":"Ο","Oslash":"Ø","Otilde":"Õ","Ouml":"Ö","Phi":"Φ","Pi":"Π","Prime":"″","Psi":"Ψ","Rho":"Ρ","Scaron":"Š","Sigma":"Σ","THORN":"Þ","Tau":"Τ","Theta":"Θ","Uacute":"Ú","Ucirc":"Û","Ugrave":"Ù","Upsilon":"Υ","Uuml":"Ü","Xi":"Ξ","Yacute":"Ý","Yuml":"Ÿ","Zeta":"Ζ","aacute":"á","acirc":"â","acute":"´","aelig":"æ","agrave":"à","alefsym":"ℵ","alpha":"α","amp":"&","and":"∧","ang":"∠","aring":"å","asymp":"≈","atilde":"ã","auml":"ä","bdquo":"„","beta":"β","brvbar":"¦","bull":"•","cap":"∩","ccedil":"ç","cedil":"¸","cent":"¢","chi":"χ","circ":"ˆ","clubs":"♣","cong":"≅","copy":"©","crarr":"↵","cup":"∪","curren":"¤","dArr":"⇓","dagger":"†","darr":"↓","deg":"°","delta":"δ","diams":"♦","divide":"÷","eacute":"é","ecirc":"ê","egrave":"è","empty":"∅","emsp":" ","ensp":" ","epsilon":"ε","equiv":"≡","eta":"η","eth":"ð","euml":"ë","euro":"€","exist":"∃","fnof":"ƒ","forall":"∀","frac12":"½","frac14":"¼","frac34":"¾","frasl":"⁄","gamma":"γ","ge":"≥","gt":">","hArr":"⇔","harr":"↔","hearts":"♥","hellip":"…","iacute":"í","icirc":"î","iexcl":"¡","igrave":"ì","image":"ℑ","infin":"∞","int":"∫","iota":"ι","iquest":"¿","isin":"∈","iuml":"ï","kappa":"κ","lArr":"⇐","lambda":"λ","lang":"〈","laquo":"«","larr":"←","lceil":"⌈","ldquo":"“","le":"≤","lfloor":"⌊","lowast":"∗","loz":"◊","lrm":"‎","lsaquo":"‹","lsquo":"‘","lt":"<","macr":"¯","mdash":"—","micro":"µ","middot":"·","minus":"−","mu":"μ","nabla":"∇","nbsp":" ","ndash":"–","ne":"≠","ni":"∋","not":"¬","notin":"∉","nsub":"⊄","ntilde":"ñ","nu":"ν","oacute":"ó","ocirc":"ô","oelig":"œ","ograve":"ò","oline":"‾","omega":"ω","omicron":"ο","oplus":"⊕","or":"∨","ordf":"ª","ordm":"º","oslash":"ø","otilde":"õ","otimes":"⊗","ouml":"ö","para":"¶","part":"∂","permil":"‰","perp":"⊥","phi":"φ","pi":"π","piv":"ϖ","plusmn":"±","pound":"£","prime":"′","prod":"∏","prop":"∝","psi":"ψ","quot":"\"","rArr":"⇒","radic":"√","rang":"〉","raquo":"»","rarr":"→","rceil":"⌉","rdquo":"”","real":"ℜ","reg":"®","rfloor":"⌋","rho":"ρ","rlm":"‏","rsaquo":"›","rsquo":"’","sbquo":"‚","scaron":"š","sdot":"⋅","sect":"§","shy":"­","sigma":"σ","sigmaf":"ς","sim":"∼","spades":"♠","sub":"⊂","sube":"⊆","sum":"∑","sup":"⊃","sup1":"¹","sup2":"²","sup3":"³","supe":"⊇","szlig":"ß","tau":"τ","there4":"∴","theta":"θ","thetasym":"ϑ","thinsp":" ","thorn":"þ","tilde":"˜","times":"×","trade":"™","uArr":"⇑","uacute":"ú","uarr":"↑","ucirc":"û","ugrave":"ù","uml":"¨","upsih":"ϒ","upsilon":"υ","uuml":"ü","weierp":"℘","xi":"ξ","yacute":"ý","yen":"¥","yuml":"ÿ","zeta":"ζ","zwj":"‍","zwnj":"‌","apos":"'"};
globalThis.XLibKindleEntities = source => source.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (whole, key) => {
    if (key[0] !== '#') return entities[key] ?? whole;
    const value = key[1].toLowerCase() === 'x' ? parseInt(key.slice(2), 16) : Number(key.slice(1));
    return value > 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff) ? String.fromCodePoint(value) : '\ufffd';
});
})();

// Derived from foliate-js mobi.js, MIT, John Factotum. See vendor/LICENSE.
// Pinned upstream 78914aef4466eb960965702401634c2cb348e9b1.
// XLib: synchronous host-sliced input, no DOM, strict KF8 selection,
// bounded decoding, malformed-reference rejection, and cancellation hooks.
(function(){
'use strict'
const unescapeHTML = str => globalThis.XLibKindleEntities(String(str ?? ''))

const MIME = {
    XML: 'application/xml',
    XHTML: 'application/xhtml+xml',
    HTML: 'text/html',
    CSS: 'text/css',
    SVG: 'image/svg+xml',
}

const PDB_HEADER = {
    name: [0, 32, 'string'],
    type: [60, 4, 'string'],
    creator: [64, 4, 'string'],
    numRecords: [76, 2, 'uint'],
}

const PALMDOC_HEADER = {
    compression: [0, 2, 'uint'],
    numTextRecords: [8, 2, 'uint'],
    recordSize: [10, 2, 'uint'],
    encryption: [12, 2, 'uint'],
}

const MOBI_HEADER = {
    magic: [16, 4, 'string'],
    length: [20, 4, 'uint'],
    type: [24, 4, 'uint'],
    encoding: [28, 4, 'uint'],
    uid: [32, 4, 'uint'],
    version: [36, 4, 'uint'],
    titleOffset: [84, 4, 'uint'],
    titleLength: [88, 4, 'uint'],
    localeRegion: [94, 1, 'uint'],
    localeLanguage: [95, 1, 'uint'],
    resourceStart: [108, 4, 'uint'],
    huffcdic: [112, 4, 'uint'],
    numHuffcdic: [116, 4, 'uint'],
    exthFlag: [128, 4, 'uint'],
    trailingFlags: [240, 4, 'uint'],
    indx: [244, 4, 'uint'],
}

const KF8_HEADER = {
    resourceStart: [108, 4, 'uint'],
    fdst: [192, 4, 'uint'],
    numFdst: [196, 4, 'uint'],
    frag: [248, 4, 'uint'],
    skel: [252, 4, 'uint'],
    guide: [260, 4, 'uint'],
}

const EXTH_HEADER = {
    magic: [0, 4, 'string'],
    length: [4, 4, 'uint'],
    count: [8, 4, 'uint'],
}

const INDX_HEADER = {
    magic: [0, 4, 'string'],
    length: [4, 4, 'uint'],
    type: [8, 4, 'uint'],
    idxt: [20, 4, 'uint'],
    numRecords: [24, 4, 'uint'],
    encoding: [28, 4, 'uint'],
    language: [32, 4, 'uint'],
    total: [36, 4, 'uint'],
    ordt: [40, 4, 'uint'],
    ligt: [44, 4, 'uint'],
    numLigt: [48, 4, 'uint'],
    numCncx: [52, 4, 'uint'],
}

const TAGX_HEADER = {
    magic: [0, 4, 'string'],
    length: [4, 4, 'uint'],
    numControlBytes: [8, 4, 'uint'],
}

const HUFF_HEADER = {
    magic: [0, 4, 'string'],
    offset1: [8, 4, 'uint'],
    offset2: [12, 4, 'uint'],
}

const CDIC_HEADER = {
    magic: [0, 4, 'string'],
    length: [4, 4, 'uint'],
    numEntries: [8, 4, 'uint'],
    codeLength: [12, 4, 'uint'],
}

const FDST_HEADER = {
    magic: [0, 4, 'string'],
    numEntries: [8, 4, 'uint'],
}

const FONT_HEADER = {
    flags: [8, 4, 'uint'],
    dataStart: [12, 4, 'uint'],
    keyLength: [16, 4, 'uint'],
    keyStart: [20, 4, 'uint'],
}

const MOBI_ENCODING = {
    1252: 'windows-1252',
    65001: 'utf-8',
}

const EXTH_RECORD_TYPE = {
    100: ['creator', 'string', true],
    101: ['publisher'],
    103: ['description'],
    104: ['isbn'],
    105: ['subject', 'string', true],
    106: ['date'],
    108: ['contributor', 'string', true],
    109: ['rights'],
    110: ['subjectCode', 'string', true],
    112: ['source', 'string', true],
    113: ['asin'],
    121: ['boundary', 'uint'],
    122: ['fixedLayout'],
    125: ['numResources', 'uint'],
    126: ['originalResolution'],
    127: ['zeroGutter'],
    128: ['zeroMargin'],
    129: ['coverURI'],
    132: ['regionMagnification'],
    201: ['coverOffset', 'uint'],
    202: ['thumbnailOffset', 'uint'],
    503: ['title'],
    524: ['language', 'string', true],
    527: ['pageProgressionDirection'],
}

const MOBI_LANG = {
    1: ['ar', 'ar-SA', 'ar-IQ', 'ar-EG', 'ar-LY', 'ar-DZ', 'ar-MA', 'ar-TN', 'ar-OM',
        'ar-YE', 'ar-SY', 'ar-JO', 'ar-LB', 'ar-KW', 'ar-AE', 'ar-BH', 'ar-QA'],
    2: ['bg'], 3: ['ca'], 4: ['zh', 'zh-TW', 'zh-CN', 'zh-HK', 'zh-SG'], 5: ['cs'],
    6: ['da'], 7: ['de', 'de-DE', 'de-CH', 'de-AT', 'de-LU', 'de-LI'], 8: ['el'],
    9: ['en', 'en-US', 'en-GB', 'en-AU', 'en-CA', 'en-NZ', 'en-IE', 'en-ZA',
        'en-JM', null, 'en-BZ', 'en-TT', 'en-ZW', 'en-PH'],
    10: ['es', 'es-ES', 'es-MX', null, 'es-GT', 'es-CR', 'es-PA', 'es-DO',
        'es-VE', 'es-CO', 'es-PE', 'es-AR', 'es-EC', 'es-CL', 'es-UY', 'es-PY',
        'es-BO', 'es-SV', 'es-HN', 'es-NI', 'es-PR'],
    11: ['fi'], 12: ['fr', 'fr-FR', 'fr-BE', 'fr-CA', 'fr-CH', 'fr-LU', 'fr-MC'],
    13: ['he'], 14: ['hu'], 15: ['is'], 16: ['it', 'it-IT', 'it-CH'],
    17: ['ja'], 18: ['ko'], 19: ['nl', 'nl-NL', 'nl-BE'], 20: ['no', 'nb', 'nn'],
    21: ['pl'], 22: ['pt', 'pt-BR', 'pt-PT'], 23: ['rm'], 24: ['ro'], 25: ['ru'],
    26: ['hr', null, 'sr'], 27: ['sk'], 28: ['sq'], 29: ['sv', 'sv-SE', 'sv-FI'],
    30: ['th'], 31: ['tr'], 32: ['ur'], 33: ['id'], 34: ['uk'], 35: ['be'],
    36: ['sl'], 37: ['et'], 38: ['lv'], 39: ['lt'], 41: ['fa'], 42: ['vi'],
    43: ['hy'], 44: ['az'], 45: ['eu'], 46: ['hsb'], 47: ['mk'], 48: ['st'],
    49: ['ts'], 50: ['tn'], 52: ['xh'], 53: ['zu'], 54: ['af'], 55: ['ka'],
    56: ['fo'], 57: ['hi'], 58: ['mt'], 59: ['se'], 62: ['ms'], 63: ['kk'],
    65: ['sw'], 67: ['uz', null, 'uz-UZ'], 68: ['tt'], 69: ['bn'], 70: ['pa'],
    71: ['gu'], 72: ['or'], 73: ['ta'], 74: ['te'], 75: ['kn'], 76: ['ml'],
    77: ['as'], 78: ['mr'], 79: ['sa'], 82: ['cy', 'cy-GB'], 83: ['gl', 'gl-ES'],
    87: ['kok'], 97: ['ne'], 98: ['fy'],
}

const concatTypedArray = (a, b) => {
    const result = new a.constructor(a.length + b.length)
    result.set(a)
    result.set(b, a.length)
    return result
}
const concatTypedArray3 = (a, b, c) => {
    const result = new a.constructor(a.length + b.length + c.length)
    result.set(a)
    result.set(b, a.length)
    result.set(c, a.length + b.length)
    return result
}

const decoder = new TextDecoder()
const getString = buffer => decoder.decode(buffer)
const getUint = buffer => {
    if (!buffer || ![1, 2, 4].includes(buffer.byteLength)) throw new Error('Invalid integer field')
    globalThis.xlibStep()
    const l = buffer.byteLength
    const func = l === 4 ? 'getUint32' : l === 2 ? 'getUint16' : 'getUint8'
    return new DataView(buffer)[func](0)
}
const getStruct = (def, buffer) => Object.fromEntries(Array.from(Object.entries(def))
    .map(([key, [start, len, type]]) => [key,
        start + len > buffer.byteLength ? undefined : (type === 'string' ? getString : getUint)(buffer.slice(start, start + len))]))

const getDecoder = x => new TextDecoder(MOBI_ENCODING[x], { fatal: true })

const getVarLen = (byteArray, i = 0) => {
    globalThis.xlibStep()
    let value = 0, length = 0
    for (const byte of byteArray.subarray(i, i + 4)) {
        value = (value << 7) | (byte & 0b111_1111) >>> 0
        length++
        if (byte & 0b1000_0000) break
    }
    if (!length || !(byteArray[i + length - 1] & 0x80)) throw new Error('Truncated variable length integer')
    return { value, length }
}

// variable-length quantity, but read from the end of data
const getVarLenFromEnd = byteArray => {
    let value = 0
    for (const byte of byteArray.subarray(-4)) {
        // `byte & 0b1000_0000` indicates the start of value
        if (byte & 0b1000_0000) value = 0
        value = (value << 7) | (byte & 0b111_1111)
    }
    return value
}

const countBitsSet = x => {
    let count = 0
    for (; x > 0; x = x >> 1) if ((x & 1) === 1) count++
    return count
}

const countUnsetEnd = x => {
    if (!x) throw new Error('Invalid zero index mask')
    let count = 0
    while ((x & 1) === 0) x = x >> 1, count++
    return count
}

const decompressPalmDOC = array => {
    let output = []
    for (let i = 0; i < array.length; i++) {
        globalThis.xlibStep()
        if (output.length > 65536) throw new Error('Text record limit exceeded')
        const byte = array[i]
        if (byte === 0) output.push(0) // uncompressed literal, just copy it
        else if (byte <= 8 && i + byte >= array.length) throw new Error('Truncated PalmDOC literal')
        else if (byte <= 8) // copy next 1-8 bytes
            for (const x of array.subarray(i + 1, (i += byte) + 1))
                output.push(x)
        else if (byte <= 0b0111_1111) output.push(byte) // uncompressed literal
        else if (byte <= 0b1011_1111) {
            // 1st and 2nd bits are 10, meaning this is a length-distance pair
            // read next byte and combine it with current byte
            if (i + 1 >= array.length) throw new Error('Truncated PalmDOC pair')
            const bytes = (byte << 8) | array[i++ + 1]
            // the 3rd to 13th bits encode distance
            const distance = (bytes & 0b0011_1111_1111_1111) >>> 3
            if (!distance || distance > output.length) throw new Error('Invalid PalmDOC back reference')
            // the last 3 bits, plus 3, is the length to copy
            const length = (bytes & 0b111) + 3
            for (let j = 0; j < length; j++)
                output.push(output[output.length - distance])
        }
        // compressed from space plus char
        else output.push(32, byte ^ 0b1000_0000)
    }
    return Uint8Array.from(output)
}

const read32Bits = (byteArray, from) => {
    const startByte = from >> 3
    const end = from + 32
    const endByte = end >> 3
    let bits = 0n
    for (let i = startByte; i <= endByte; i++)
        bits = bits << 8n | BigInt(byteArray[i] ?? 0)
    return (bits >> (8n - BigInt(end & 7))) & 0xffffffffn
}

const huffcdic = (mobi, loadRecord) => {
    const huffRecord = loadRecord(mobi.huffcdic)
    const { magic, offset1, offset2 } = getStruct(HUFF_HEADER, huffRecord)
    if (magic !== 'HUFF') throw new Error('Invalid HUFF record')

    // table1 is indexed by byte value
    const table1 = Array.from({ length: 256 }, (_, i) => offset1 + i * 4)
        .map(offset => getUint(huffRecord.slice(offset, offset + 4)))
        .map(x => [x & 0b1000_0000, x & 0b1_1111, x >>> 8])

    // table2 is indexed by code length
    const table2 = [null].concat(Array.from({ length: 32 }, (_, i) => offset2 + i * 8)
        .map(offset => [
            getUint(huffRecord.slice(offset, offset + 4)),
            getUint(huffRecord.slice(offset + 4, offset + 8))]))

    const dictionary = []
    for (let i = 1; i < mobi.numHuffcdic; i++) {
        const record = loadRecord(mobi.huffcdic + i)
        const cdic = getStruct(CDIC_HEADER, record)
        if (cdic.magic !== 'CDIC') throw new Error('Invalid CDIC record')
        // `numEntries` is the total number of dictionary data across CDIC records
        // so `n` here is the number of entries in *this* record
        if (cdic.codeLength > 20 || cdic.numEntries > 1048576) throw new Error('Dictionary limit exceeded')
        const n = Math.min(1 << cdic.codeLength, cdic.numEntries - dictionary.length)
        const buffer = record.slice(cdic.length)
        for (let i = 0; i < n; i++) {
            const offset = getUint(buffer.slice(i * 2, i * 2 + 2))
            const x = getUint(buffer.slice(offset, offset + 2))
            const length = x & 0x7fff
            const decompressed = x & 0x8000
            const value = new Uint8Array(
                buffer.slice(offset + 2, offset + 2 + length))
            dictionary.push([value, decompressed])
        }
    }

    const active = new Set()
    const decompress = byteArray => {
        let output = new Uint8Array()
        const bitLength = byteArray.byteLength * 8
        for (let i = 0; i < bitLength;) {
            globalThis.xlibStep()
            if (output.length > 65536) throw new Error('Text record limit exceeded')
            const bits = Number(read32Bits(byteArray, i))
            let [found, codeLength, value] = table1[bits >>> 24]
            if (!found) {
                while (codeLength <= 32 && bits >>> (32 - codeLength) < table2[codeLength][0]) codeLength += 1
                if (codeLength > 32) throw new Error('Invalid Huffman code')
                value = table2[codeLength][1]
            }
            if ((i += codeLength) > bitLength) break

            const code = value - (bits >>> (32 - codeLength))
            if (!dictionary[code] || active.has(code) || active.size >= 32) throw new Error('Invalid Huffman dictionary reference')
            let [result, decompressed] = dictionary[code]
            if (!decompressed) {
                // the result is itself compressed
                active.add(code)
                result = decompress(result)
                active.delete(code)
                // cache the result for next time
                dictionary[code] = [result, true]
            }
            output = concatTypedArray(output, result)
        }
        return output
    }
    return decompress
}

const getIndexData = (indxIndex, loadRecord) => {
    const indxRecord = loadRecord(indxIndex)
    const indx = getStruct(INDX_HEADER, indxRecord)
    if (indx.magic !== 'INDX') throw new Error('Invalid INDX record')
    if (indx.numRecords > 65535 || indx.numCncx > 65535 || indx.length > indxRecord.byteLength) throw new Error('Index limit exceeded')
    const decoder = getDecoder(indx.encoding)

    const tagxBuffer = indxRecord.slice(indx.length)
    const tagx = getStruct(TAGX_HEADER, tagxBuffer)
    if (tagx.magic !== 'TAGX') throw new Error('Invalid TAGX section')
    if (tagx.length < 12 || tagx.length > tagxBuffer.byteLength || tagx.length > 65536 || !tagx.numControlBytes || tagx.numControlBytes > 256) throw new Error('Invalid TAGX size')
    const numTags = (tagx.length - 12) / 4
    const tagTable = Array.from({ length: numTags }, (_, i) =>
        new Uint8Array(tagxBuffer.slice(12 + i * 4, 12 + i * 4 + 4)))

    const cncx = {}
    let cncxRecordOffset = 0
    for (let i = 0; i < indx.numCncx; i++) {
        const record = loadRecord(indxIndex + indx.numRecords + i + 1)
        const array = new Uint8Array(record)
        for (let pos = 0; pos < array.byteLength;) {
            const index = pos
            const { value, length } = getVarLen(array, pos)
            pos += length
            const result = record.slice(pos, pos + value)
            pos += value
            cncx[cncxRecordOffset + index] = decoder.decode(result)
        }
        cncxRecordOffset += 0x10000
    }

    const table = []
    for (let i = 0; i < indx.numRecords; i++) {
        const record = loadRecord(indxIndex + 1 + i)
        const array = new Uint8Array(record)
        const indx = getStruct(INDX_HEADER, record)
        if (indx.magic !== 'INDX') throw new Error('Invalid INDX record')
        if (indx.numRecords > 65535 || indx.idxt + 4 + indx.numRecords * 2 > record.byteLength) throw new Error('Index entries out of bounds')
        for (let j = 0; j < indx.numRecords; j++) {
            const offsetOffset = indx.idxt + 4 + 2 * j
            const offset = getUint(record.slice(offsetOffset, offsetOffset + 2))

            const length = getUint(record.slice(offset, offset + 1))
            const name = getString(record.slice(offset + 1, offset + 1 + length))

            const tags = []
            const startPos = offset + 1 + length
            let controlByteIndex = 0
            let pos = startPos + tagx.numControlBytes
            for (const [tag, numValues, mask, end] of tagTable) {
                if (end & 1) {
                    controlByteIndex++
                    continue
                }
                const offset = startPos + controlByteIndex
                if (offset >= record.byteLength) throw new Error('Index control byte out of bounds')
                const value = getUint(record.slice(offset, offset + 1)) & mask
                if (value === mask) {
                    if (countBitsSet(mask) > 1) {
                        const { value, length } = getVarLen(array, pos)
                        tags.push([tag, null, value, numValues])
                        pos += length
                    } else tags.push([tag, 1, null, numValues])
                } else tags.push([tag, value >> countUnsetEnd(mask), null, numValues])
            }

            const tagMap = {}
            for (const [tag, valueCount, valueBytes, numValues] of tags) {
                const values = []
                if (valueCount != null) {
                    for (let i = 0; i < valueCount * numValues; i++) {
                        const { value, length } = getVarLen(array, pos)
                        values.push(value)
                        pos += length
                    }
                } else {
                    let count = 0
                    while (count < valueBytes) {
                        const { value, length } = getVarLen(array, pos)
                        values.push(value)
                        pos += length
                        count += length
                    }
                }
                tagMap[tag] = values
            }
            table.push({ name, tagMap })
        }
    }
    return { table, cncx }
}

const getNCX = (indxIndex, loadRecord) => {
    const { table, cncx } = getIndexData(indxIndex, loadRecord)
    const items = table.map(({ tagMap }, index) => ({
        index,
        offset: tagMap[1]?.[0],
        size: tagMap[2]?.[0],
        label: cncx[tagMap[3]] ?? '',
        headingLevel: tagMap[4]?.[0],
        pos: tagMap[6],
        parent: tagMap[21]?.[0],
        firstChild: tagMap[22]?.[0],
        lastChild: tagMap[23]?.[0],
    }))
    const byParent = new Map()
    for (const item of items) {
        globalThis.xlibStep()
        if (!byParent.has(item.parent)) byParent.set(item.parent, [])
        byParent.get(item.parent).push(item)
    }
    const visiting = new Set()
    const getChildren = (item, depth = 0) => {
        globalThis.xlibStep()
        if (depth > 32 || visiting.has(item.index)) throw new Error('Invalid NCX hierarchy')
        if (item.firstChild == null) return item
        visiting.add(item.index)
        item.children = (byParent.get(item.index) ?? []).map(x => getChildren(x, depth + 1))
        visiting.delete(item.index)
        return item
    }
    return items.filter(item => item.headingLevel === 0).map(x => getChildren(x))
}

const getEXTH = (buf, encoding) => {
    const { magic, count } = getStruct(EXTH_HEADER, buf)
    if (magic !== 'EXTH') throw new Error('Invalid EXTH header')
    const decoder = getDecoder(encoding)
    const results = {}
    let offset = 12
    for (let i = 0; i < count; i++) {
        const type = getUint(buf.slice(offset, offset + 4))
        const length = getUint(buf.slice(offset + 4, offset + 8))
        if (type in EXTH_RECORD_TYPE) {
            const [name, typ, many] = EXTH_RECORD_TYPE[type]
            const data = buf.slice(offset + 8, offset + length)
            const value = typ === 'uint' ? getUint(data) : decoder.decode(data)
            if (many) {
                results[name] ??= []
                results[name].push(value)
            } else results[name] = value
        }
        offset += length
    }
    return results
}

const getFont = (buf, unzlib) => {
    const { flags, dataStart, keyLength, keyStart } = getStruct(FONT_HEADER, buf)
    const array = new Uint8Array(buf.slice(dataStart))
    // deobfuscate font
    if (flags & 0b10) {
        const bytes = keyLength === 16 ? 1024 : 1040
        const key = new Uint8Array(buf.slice(keyStart, keyStart + keyLength))
        const length = Math.min(bytes, array.length)
        for (var i = 0; i < length; i++) array[i] = array[i] ^ key[i % key.length]
    }
    // decompress font
    if (flags & 1) try {
        return unzlib(array)
    } catch (e) {
        console.warn(e)
        console.warn('Failed to decompress font')
    }
    return array
}

const isMOBI = file => {
    const magic = getString(file.slice(60, 68).arrayBuffer())
    return magic === 'BOOKMOBI'// || magic === 'TEXtREAd'
}

class PDB {
    #file
    #offsets
    pdb
    open(file) {
        this.#file = file
        const pdb = getStruct(PDB_HEADER, file.slice(0, 78).arrayBuffer())
        this.pdb = pdb
        const buffer = file.slice(78, 78 + pdb.numRecords * 8).arrayBuffer()
        // get start and end offsets for each record
        this.#offsets = Array.from({ length: pdb.numRecords },
            (_, i) => getUint(buffer.slice(i * 8, i * 8 + 4)))
            .map((x, i, a) => [x, a[i + 1]])
    }
    loadRecord(index) {
        const offsets = this.#offsets[index]
        if (!offsets) throw new RangeError('Record index out of bounds')
        return this.#file.slice(...offsets).arrayBuffer()
    }
    loadMagic(index) {
        const start = this.#offsets[index][0]
        return getString(this.#file.slice(start, start + 4).arrayBuffer())
    }
}

class MOBI extends PDB {
    #start = 0
    #resourceStart
    #decoder
    #encoder
    #decompress
    #removeTrailingEntries
    constructor({ unzlib }) {
        super()
        this.unzlib = unzlib
    }
    open(file) {
        super.open(file)
        // TODO: if (this.pdb.type === 'TEXt')
        this.headers = this.#getHeaders(super.loadRecord(0))
        this.#resourceStart = this.headers.mobi.resourceStart
        let isKF8 = this.headers.mobi.version >= 8
        if (!isKF8) {
            const boundary = this.headers.exth?.boundary
            if (boundary < 0xffffffff) {
                this.headers = this.#getHeaders(super.loadRecord(boundary))
                this.#start = boundary
                isKF8 = true
            }
        }
        this.#setup()
        return this
    }
    #getHeaders(buf) {
        const palmdoc = getStruct(PALMDOC_HEADER, buf)
        const mobi = getStruct(MOBI_HEADER, buf)
        if (mobi.magic !== 'MOBI') throw new Error('Missing MOBI header')
        if (mobi.length < 228) mobi.trailingFlags = 0
        if (mobi.length < 232) mobi.indx = 0xffffffff

        const { titleOffset, titleLength, localeLanguage, localeRegion } = mobi
        mobi.title = buf.slice(titleOffset, titleOffset + titleLength)
        const lang = MOBI_LANG[localeLanguage]
        mobi.language = lang?.[localeRegion >> 2] ?? lang?.[0]

        const exth = mobi.exthFlag & 0b100_0000
            ? getEXTH(buf.slice(mobi.length + 16), mobi.encoding) : null
        const kf8 = mobi.version >= 8 ? getStruct(KF8_HEADER, buf) : null
        return { palmdoc, mobi, exth, kf8 }
    }
    #setup() {
        const { palmdoc, mobi } = this.headers
        this.#decoder = getDecoder(mobi.encoding)
        // `TextEncoder` only supports UTF-8
        // we are only encoding ASCII anyway, so I think it's fine
        this.#encoder = new TextEncoder()

        // set up decompressor
        const { compression } = palmdoc
        this.#decompress = compression === 1 ? f => f
            : compression === 2 ? decompressPalmDOC
            : compression === 17480 ? huffcdic(mobi, this.loadRecord.bind(this))
            : null
        if (!this.#decompress) throw new Error('Unknown compression type')

        // set up function for removing trailing bytes
        const { trailingFlags } = mobi
        const multibyte = trailingFlags & 1
        const numTrailingEntries = countBitsSet(trailingFlags >>> 1)
        this.#removeTrailingEntries = array => {
            for (let i = 0; i < numTrailingEntries; i++) {
                const length = getVarLenFromEnd(array)
                if (!Number.isInteger(length) || length <= 0 || length > array.length) throw new Error('Invalid trailing record')
                array = array.subarray(0, -length)
            }
            if (multibyte) {
                const length = (array[array.length - 1] & 0b11) + 1
                if (length > array.length) throw new Error('Invalid multibyte trailer')
                array = array.subarray(0, -length)
            }
            return array
        }
    }
    decode(...args) {
        return this.#decoder.decode(...args)
    }
    encode(...args) {
        return this.#encoder.encode(...args)
    }
    loadRecord(index) {
        return super.loadRecord(this.#start + index)
    }
    loadMagic(index) {
        return super.loadMagic(this.#start + index)
    }
    loadText(index) {
        return this.#decompress(this.#removeTrailingEntries(new Uint8Array(this.loadRecord(index + 1))))
    }
    loadResource(index) {
        const buf = super.loadRecord(this.#resourceStart + index)
        const magic = getString(buf.slice(0, 4))
        if (magic === 'FONT') return getFont(buf, this.unzlib)
        if (magic === 'VIDE' || magic === 'AUDI') return buf.slice(12)
        return buf
    }
    getNCX() {
        const index = this.headers.mobi.indx
        if (index < 0xffffffff) return getNCX(index, this.loadRecord.bind(this))
    }
    getMetadata() {
        const { mobi, exth } = this.headers
        return {
            identifier: mobi.uid.toString(),
            title: unescapeHTML(exth?.title || this.decode(mobi.title)),
            author: exth?.creator?.map(unescapeHTML),
            publisher: unescapeHTML(exth?.publisher),
            language: exth?.language ?? mobi.language,
            published: exth?.date,
            description: unescapeHTML(exth?.description),
            subject: exth?.subject?.map(unescapeHTML),
            rights: unescapeHTML(exth?.rights),
            contributor: exth?.contributor,
        }
    }
    getCover() {
        const { exth } = this.headers
        const offset = exth?.coverOffset < 0xffffffff ? exth?.coverOffset
            : exth?.thumbnailOffset < 0xffffffff ? exth?.thumbnailOffset : null
        if (offset != null) {
            const buf = this.loadResource(offset)
            return new Blob([buf])
        }
    }
}


globalThis.XLibMOBI = { MOBI, getIndexData }
})();


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
