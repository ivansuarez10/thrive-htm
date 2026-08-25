#!/usr/bin/env node
/* ═══════════════════════════════════════════════════════════
   THRIVE — generador de las landings

   Lee config.js y _template-landing.html, y escribe:
     index.html                  redirección de la raíz a /thrive/
     thrive/index.html           landing sin nombre (para redes)
     thrive/<slug>/index.html    una por clienta, con el nombre horneado

   Correr cada vez que cambien las referidas en config.js:
     node build.js

   Los assets se referencian desde la raíz del dominio (/assets/…),
   no en relativo. Por eso la profundidad de la carpeta ya no importa
   y no hace falta sustituir ninguna base. Requiere servir el sitio
   desde la raíz de un dominio — que es justo lo que hace
   healingthroughmovement.studio. Abrir los archivos con doble clic
   (file://) ya no funciona; usar el servidor local.
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

/* Slugs que ya son rutas del sitio. Una clienta que se llamara así
   taparía el formulario o la confirmación de la clase. */
const RESERVADOS = new Set(['form', 'schedule', 'assets']);

/* Escapa lo que se mete en un atributo HTML */
const attr = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
  .replace(/</g, '&lt;').replace(/>/g, '&gt;');

function escribir(destino, referida) {
  const html = tpl.replace(/\{\{DATA_REFERIDA\}\}/g,
    referida ? ` data-referida="${attr(referida)}"` : '');
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  fs.writeFileSync(destino, html);
  return html.length;
}

/* 1 · la raíz del dominio manda a la invitación.
   El día que HTM tenga home propia, este archivo se reemplaza. */
const redir = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=/thrive/">
<link rel="canonical" href="https://healingthroughmovement.studio/thrive/">
<meta name="robots" content="noindex, nofollow">
<title>Healing Through Movement</title>
</head>
<body>
<p>Ir a <a href="/thrive/">THRIVE</a>.</p>
<script>location.replace('/thrive/');</script>
</body>
</html>
`;
fs.writeFileSync(path.join(raiz, 'index.html'), redir);
console.log('✓ index.html'.padEnd(36) + '→ /thrive/');

/* 2 · landing sin nombre */
let n = escribir(path.join(raiz, 'thrive', 'index.html'), null);
console.log(`✓ thrive/index.html`.padEnd(36) + `(sin nombre)`.padEnd(14) + `${(n/1024).toFixed(0)} KB`);

/* 3 · una por clienta */
const vistos = new Set();

for (const r of CFG.referidas) {
  if (!r || !r.slug || !r.nombre) { console.warn('⚠ entrada incompleta, se salta:', r); continue; }
  if (!/^[a-z0-9-]+$/.test(r.slug)) {
    console.warn(`⚠ slug inválido "${r.slug}" — solo minúsculas, números y guiones. Se salta.`);
    continue;
  }
  if (RESERVADOS.has(r.slug)) {
    console.warn(`⚠ slug reservado "${r.slug}" — esa ruta ya es del sitio. Se salta.`);
    continue;
  }
  if (vistos.has(r.slug)) { console.warn(`⚠ slug repetido "${r.slug}", se salta`); continue; }
  vistos.add(r.slug);

  const size = escribir(path.join(raiz, 'thrive', r.slug, 'index.html'), r.nombre);
  console.log(`✓ thrive/${r.slug}/index.html`.padEnd(36) + `${r.nombre}`.padEnd(14) + `${(size/1024).toFixed(0)} KB`);
}

/* 4 · barrer landings de clientas que ya no están en config.
   Si a alguien se le quita el link, su página tiene que dejar de existir,
   no quedarse publicada porque nadie la borró a mano. */
const barridas = [];
for (const entrada of fs.readdirSync(path.join(raiz, 'thrive'), { withFileTypes: true })) {
  if (!entrada.isDirectory()) continue;
  if (RESERVADOS.has(entrada.name) || vistos.has(entrada.name)) continue;
  fs.rmSync(path.join(raiz, 'thrive', entrada.name), { recursive: true, force: true });
  barridas.push(entrada.name);
}
if (barridas.length) console.log(`\n· barridas (ya no están en config): ${barridas.join(', ')}`);

/* 5 · avisos que importan antes de publicar */
console.log('');
const pendientes = [];
if (!CFG.whatsapp || /^5040+$/.test(CFG.whatsapp) || CFG.whatsapp === '50400000000')
  pendientes.push('El WhatsApp de Denisse sigue siendo un número de relleno — los botones no funcionan.');
if (!/^https:\/\/healingthroughmovement\.studio$/.test((CFG.baseUrl || '').replace(/\/$/, '')))
  pendientes.push(`baseUrl es "${CFG.baseUrl}" — debería ser https://healingthroughmovement.studio`);
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
console.log(`\n${vistos.size} landings con nombre + 1 sin nombre + la redirección de la raíz.`);
