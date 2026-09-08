// node --expose-gc Tests/OC_KakuteiExtractor/benchmark.js <baseline|current> <Code.gs> <students> <matrix width>
// GASのサービス呼出しを含まないV8合成比較。実シートは読み書きしない。
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const { performance } = require('node:perf_hooks');
const [mode, sourcePath, countText, widthText] = process.argv.slice(2);
if (!['baseline', 'current'].includes(mode)) throw new Error('baseline/current を指定してください');
const count = Number(countText), width = Number(widthText), dates = 300, firstColumn = 3;
const t = vm.createContext({});
vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), t);
const config = t.ocKakuteiGetConfig_();
const info = {
  dataStartIndex: firstColumn, dataWidth: dates + 4,
  studentIdIndex: firstColumn, nameIndex: firstColumn + 1, furiganaIndex: firstColumn + 2, saTaIndex: firstColumn + 3,
  outputIndexes: Array.from({ length: dates + 4 }, (_, i) => firstColumn + i),
  targetDateColumns: Array.from({ length: dates }, (_, i) => ({ index: firstColumn + 4 + i, confirmationLabel: new Date(Date.UTC(2026, 0, i + 1)).toISOString().slice(0, 10) })),
};
const matrix = [Array(width).fill('対象外')];
for (let i = 0; i < count; i++) {
  const row = Array(width).fill('対象外');
  row.splice(firstColumn, dates + 4, ` Ａ${String(i).padStart(3, '0')} `, `学生 ${i}`, 'ﾔﾏﾀﾞ', ' ＳＡ ', ...Array(dates).fill('〇'));
  matrix.push(row);
}
global.gc?.();
const initial = process.memoryUsage();
const measured = [];
let hashes = [], outputHash, outputBytes;
for (const retain of [false, true]) {
  const start = performance.now();
  const input = mode === 'baseline' ? matrix.slice(1).map(row => row.slice(info.dataStartIndex, info.dataStartIndex + info.dataWidth)) : matrix;
  const result = mode === 'baseline'
    ? t.ocKakuteiValidateStudentRows_(config, input, info, 2, retain)
    : t.ocKakuteiValidateStudentRows_(config, input, info, 2, retain, 1, 0);
  const validated = process.memoryUsage();
  const serialized = JSON.stringify({ relevantRows: result.fingerprintRows });
  hashes.push(crypto.createHash('sha256').update(serialized).digest('hex'));
  const fingerprinted = process.memoryUsage();
  if (retain) {
    const output = t.ocKakuteiBuildCopyOutput_(result.records).copyText;
    outputBytes = Buffer.byteLength(output);
    outputHash = crypto.createHash('sha256').update(output).digest('hex');
  }
  measured.push({ retain, elapsedMs: performance.now() - start, validatedHeap: validated.heapUsed, fingerprintedHeap: fingerprinted.heapUsed, afterOutputHeap: process.memoryUsage().heapUsed });
}
if (hashes[0] !== hashes[1]) throw new Error('2回の読込の指紋が一致しません');
console.log(JSON.stringify({ mode, students: count, dateColumns: dates, cells: matrix.length * width, startHeap: initial.heapUsed, maxRssBytes: process.resourceUsage().maxRSS * 1024, measured, fingerprint: hashes[0], outputHash, outputBytes,
  slicedCellReferences: mode === 'baseline' ? count * info.dataWidth : 0,
  duplicatedFingerprintReferences: mode === 'baseline' ? count * (info.dataWidth + 1) : 0,
}));
