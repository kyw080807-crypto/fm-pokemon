// Runs Poké Manager's own buildWorld() under Node with a seeded Math.random and
// writes the rosters it generates, so the random parts of the starting world
// (24 non-canon trainers, and filler mons for canon rosters under 3) become
// fixed data. The game's code is executed unchanged; only the browser globals
// it touches at load time are stubbed.
//
//   node tools/pokemanager/lock_rosters.js [seed]
//   in:  import/pokemanager/resources/index.html  (tools/pokemanager/asar.rb extract)
//   out: tools/pokemanager/data/rosters.json       (committed)
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'import', 'pokemanager', 'resources', 'index.html');
const OUT = path.join(__dirname, 'data', 'rosters.json');
const SEED = Number(process.argv[2] || 20261027);

// mulberry32: small, well-known 32-bit seeded PRNG returning [0, 1).
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// A do-anything stand-in for DOM objects: every property is another stub and
// calling it returns a stub, so UI setup code at load time doesn't throw.
function stub() {
  const fn = function () { return stub(); };
  return new Proxy(fn, {
    get(target, key) {
      if (key === Symbol.toPrimitive) return () => '';
      if (key === Symbol.iterator) return function* () {};
      if (key === 'length') return 0;
      if (key === 'then') return undefined;
      return stub();
    },
    set() { return true; },
    apply() { return stub(); },
    construct() { return stub(); },
  });
}

const storage = new Map();
const sandbox = {
  console: { log() {}, warn() {}, error() {}, info() {}, debug() {} },
  setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {},
  requestAnimationFrame: () => 0, cancelAnimationFrame() {},
  document: stub(), navigator: { language: 'ko-KR', userAgent: 'node' },
  location: { search: '', hash: '', href: 'http://localhost/' },
  localStorage: {
    getItem: k => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)), removeItem: k => storage.delete(k),
  },
  Audio: function () { return stub(); }, Image: function () { return stub(); },
  fetch: () => new Promise(() => {}), Neutralino: stub(),
  matchMedia: () => ({ matches: false, addEventListener() {} }),
  addEventListener() {}, removeEventListener() {},
};
sandbox.window = sandbox; sandbox.self = sandbox; sandbox.globalThis = sandbox;
const ctx = vm.createContext(sandbox);
// Seed before any game script captures `const rnd = Math.random`.
vm.runInContext(`Math.random = (${mulberry32.toString()})(${SEED});`, ctx);

const html = fs.readFileSync(SRC, 'utf8');
const scripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const failures = [];
scripts.forEach((code, i) => {
  try { vm.runInContext(code, ctx, { filename: `script${i}.js` }); }
  catch (e) { failures.push(`script${i}: ${e && e.message}`); }
});
if (typeof vm.runInContext('typeof buildWorld', ctx) === 'undefined' ||
    vm.runInContext('typeof buildWorld', ctx) !== 'function') {
  console.error('buildWorld not defined; script errors:\n' + failures.join('\n'));
  process.exit(1);
}

vm.runInContext('buildWorld()', ctx);
const result = vm.runInContext(`(() => {
  const REGION = ${JSON.stringify(['관동', '성도', '호연', '신오', '하나', '칼로스', '알로라', '가라르', '팔데아'])};
  return S.trainers.map(T => ({
    region: T.region, region_name: REGION[T.region], role: T.role, name: T.name, canon: T.canon,
    mons: T.mons.map(m => ({
      num: SP[m.sp].num, species: SP[m.sp].n, form: SP[m.sp].form ? (SP[m.sp].fm || SP[m.sp].key || true) : null,
      canon: !!m.canon, level: m.lvl, stars: m.stars, iv: m.iv,
    })),
  }));
})()`, ctx);

const locked = result.map(t => ({ ...t, mons: t.mons.filter(m => !m.canon) }))
  .filter(t => t.mons.length > 0);
const out = {
  source: 'Poké Manager buildWorld() (resources.neu index.html), run by tools/pokemanager/lock_rosters.js',
  seed: SEED,
  note: 'Only mons that buildWorld() picks at random: full rosters of non-canon trainers and filler mons ' +
        'added to canon rosters with fewer than 3. Canon roster species come from TRAINERS; their IVs/levels ' +
        'are also random in buildWorld() and are not locked here.',
  trainers: locked,
};
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n');

const nonCanon = locked.filter(t => !t.canon);
console.log(`seed ${SEED}; scripts ${scripts.length}, load errors ${failures.length}`);
failures.forEach(f => console.log('  ' + f.slice(0, 160)));
console.log(`trainers ${result.length}; locked: ${nonCanon.length} non-canon, ` +
            `${locked.length - nonCanon.length} canon with filler`);
console.log(`wrote ${path.relative(ROOT, OUT)}`);
