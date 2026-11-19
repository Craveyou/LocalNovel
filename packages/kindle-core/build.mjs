import { readFileSync, writeFileSync } from 'node:fs';
const root = new URL('./', import.meta.url);
const files = ['entities.js', 'vendor/mobi.decoder.js', 'core.js'];
const generated = '// Generated from packages/kindle-core; run node packages/kindle-core/build.mjs.\n' + files.map(p => readFileSync(new URL(p, root), 'utf8')).join('\n');
const target = new URL('../apple-shared/Sources/AppleShared/Resources/kindle-core.js', root);
if (process.argv.includes('--check')) {
    if (readFileSync(target, 'utf8') !== generated) throw new Error('Kindle shared bundle is stale');
    const license = readFileSync(new URL('vendor/LICENSE', root), 'utf8').trim();
    for (const path of ['../apple-shared/Sources/AppleShared/Resources/KindleCore-LICENSE.txt',
        '../../apps/ios/XLibReader/Resources/KindleCore-LICENSE.txt']) {
        if (readFileSync(new URL(path, root), 'utf8').trim() !== license)
            throw new Error(`Kindle redistributed MIT license is stale: ${path}`);
    }
} else writeFileSync(target, generated);
