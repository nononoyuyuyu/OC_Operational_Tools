'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const sourceDir = path.resolve(__dirname, '../../Source/OC_ThreeMonthBlankHighlighter');
function load(globals = {}) {
  const context = vm.createContext({ ...globals });
  for (const file of ['Core.gs', 'Code.gs']) {
    vm.runInContext(fs.readFileSync(path.join(sourceDir, file), 'utf8'), context, { filename: file });
  }
  return context;
}
function formatDate(date, zone, pattern) {
  if (pattern !== 'yyyy/MM/dd') throw Error('未対応の日時形式');
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const p = Object.fromEntries(parts.map(item => [item.type, item.value]));
  return `${p.year}/${p.month}/${p.day}`;
}
const utilities = { formatDate, DigestAlgorithm: { SHA_256: 'SHA_256' }, Charset: { UTF_8: 'UTF_8' },
  computeDigest: (_algorithm, text) => [...crypto.createHash('sha256').update(text).digest()] };
const plain = value => JSON.parse(JSON.stringify(value));
module.exports = { load, formatDate, utilities, plain, sourceDir };
