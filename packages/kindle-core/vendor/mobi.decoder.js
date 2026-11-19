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

