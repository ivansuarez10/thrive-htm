#!/usr/bin/env node
/* ═══════════════════════════════════════════════════════════
   THRIVE — generador de las landings

   Lee config.js y _template-landing.html, y escribe:
     index.html            landing sin nombre (para redes)
     i/<slug>/index.html   una por clienta, con el nombre horneado

   Correr cada vez que cambien las referidas en config.js:
     node build.js
   ═══════════════════════════════════════════════════════════ */

const fs = require('fs');
const path = require('path');

const raiz = __dirname;
const tpl = fs.readFileSync(path.join(raiz, '_template-landing.html'), 'utf8');

/* config.js define window.THRIVE — se evalúa con un window de mentira */
const cfgSrc = fs.readFileSync(path.join(raiz, 'config.js'), 'utf8');
const sandbox = { window: {} };
new Function('window', cfgSrc)(sandbox.window);
const CFG = sandbox.window.THRIVE;

if (!CFG || !Array.isArray(CFG.referidas)) {
  console.error('✗ config.js no define window.THRIVE.referidas');
  process.exit(1);
}

/* Escapa lo que se mete en un atributo HTML */
const attr = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
  .replace(/</g, '&lt;').replace(/>/g, '&gt;');

function escribir(destino, base, referida) {
  const html = tpl
    .replace(/\{\{BASE\}\}/g, base)
    .replace(/\{\{DATA_REFERIDA\}\}/g, referida ? ` data-referida="${attr(referida)}"` : '');
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  fs.writeFileSync(destino, html);
  return html.length;
}

/* 1 · landing sin nombre */
let n = escribir(path.join(raiz, 'index.html'), '', null);
console.log(`✓ index.html                      (sin nombre)  ${(n/1024).toFixed(0)} KB`);

/* 2 · una por clienta */
const vistos = new Set();
let generadas = 0;

for (const r of CFG.referidas) {
  if (!r || !r.slug || !r.nombre) { console.warn('⚠ entrada incompleta, se salta:', r); continue; }
  if (!/^[a-z0-9-]+$/.test(r.slug)) {
    console.warn(`⚠ slug inválido "${r.slug}" — solo minúsculas, números y guiones. Se salta.`);
    continue;
  }
  if (vistos.has(r.slug)) { console.warn(`⚠ slug repetido "${r.slug}", se salta`); continue; }
  vistos.add(r.slug);

  const size = escribir(path.join(raiz, 'i', r.slug, 'index.html'), '../../', r.nombre);
  console.log(`✓ i/${r.slug}/index.html`.padEnd(34) + `${r.nombre}`.padEnd(14) + `${(size/1024).toFixed(0)} KB`);
  generadas++;
}

/* 3 · avisos que importan antes de publicar */
console.log('');
const pendientes = [];
if (!CFG.whatsapp || /^5040+$/.test(CFG.whatsapp) || CFG.whatsapp === '50400000000')
  pendientes.push('El WhatsApp de Denisse sigue siendo un número de relleno — los botones no funcionan.');
if (!CFG.supabase || !CFG.supabase.enabled)
  pendientes.push('Supabase apagado: el screening funciona pero las respuestas no se guardan.');
if (!CFG.clase || !CFG.clase.mapa)
  pendientes.push('Falta el link de Google Maps de la clase.');
if (!CFG.clase || /pendiente/i.test(CFG.clase.direccion || ''))
  pendientes.push('Falta la dirección exacta del estudio.');

if (pendientes.length) {
  console.log('Antes de publicar:');
  pendientes.forEach(p => console.log('  · ' + p));
} else {
  console.log('Sin pendientes. Listo para publicar.');
}
console.log(`\n${generadas} landings con nombre + 1 sin nombre.`);
