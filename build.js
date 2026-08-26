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
const crypto = require('crypto');

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

/* 5 · sellar los assets con la huella de su contenido.
   Sin esto, un navegador que ya visitó el sitio se queda con el CSS o el
   JS viejo hasta diez minutos (Pages manda cache-control: max-age=600) y
   ve el HTML nuevo sin sus estilos. Al cambiar la huella, la URL cambia y
   el navegador está obligado a bajarlo de nuevo. */
function huella(rel) {
  const abs = path.join(raiz, rel);
  if (!fs.existsSync(abs)) return null;
  return crypto.createHash('sha1').update(fs.readFileSync(abs)).digest('hex').slice(0, 8);
}

const SELLOS = {
  '/assets/css/thrive.css': huella('assets/css/thrive.css'),
  '/assets/js/thrive.js':   huella('assets/js/thrive.js'),
  '/config.js':             huella('config.js')
};

function htmlsDe(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git' || e.name === 'node_modules') continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...htmlsDe(full));
    else if (e.name.endsWith('.html') && e.name !== '_template-landing.html') out.push(full);
  }
  return out;
}

let sellados = 0;
for (const f of htmlsDe(raiz)) {
  let html = fs.readFileSync(f, 'utf8');
  const antes = html;
  for (const [ruta, sello] of Object.entries(SELLOS)) {
    if (!sello) continue;
    const re = new RegExp(ruta.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(\\?v=[a-f0-9]+)?', 'g');
    html = html.replace(re, ruta + '?v=' + sello);
  }
  if (html !== antes) { fs.writeFileSync(f, html); sellados++; }
}
console.log(`\n· ${sellados} páginas selladas · css ${SELLOS['/assets/css/thrive.css']} · js ${SELLOS['/assets/js/thrive.js']} · config ${SELLOS['/config.js']}`);

/* 6 · avisos que importan antes de publicar */
console.log('');
const pendientes = [];
if (!CFG.whatsapp || /^5040+$/.test(CFG.whatsapp) || CFG.whatsapp === '50400000000')
  pendientes.push('El WhatsApp de Denisse sigue siendo un número de relleno — los botones no funcionan.');
if (!/^https:\/\/healingthroughmovement\.studio$/.test((CFG.baseUrl || '').replace(/\/$/, '')))
  pendientes.push(`baseUrl es "${CFG.baseUrl}" — debería ser https://healingthroughmovement.studio`);
if (!CFG.supabase || !CFG.supabase.enabled)
  pendientes.push('Supabase apagado: el screening funciona pero las respuestas no se guardan.');
if (!CFG.clase || !CFG.clase.mapa)
  pendientes.push('Falta el link de la ficha de HTM en Google Maps — sin él la confirmación no lleva a nadie al estudio.');
if (!CFG.clase || !CFG.clase.direccion)
  pendientes.push('Falta la dirección exacta: Google Calendar no puede abrir navegación sin ella.');
/* El aviso de los nombres de ejemplo murió con la lista: desde el 26 ago
   el link de invitación es uno solo y sin personalizar, así que no hay
   nombres que confirmar. Si alguna vez vuelven las landings por clienta,
   este aviso vuelve con ellas. */

/* La fecha de la clase de prueba ya no vive acá: Denisse se la asigna a
   cada clienta desde el panel, y el link del pase la lleva adentro. Este
   aviso avisaba de una fecha global que la página ya no lee, así que era
   una alarma falsa en cada build. */

if (pendientes.length) {
  console.log('Antes de publicar:');
  pendientes.forEach(p => console.log('  · ' + p));
} else {
  console.log('Sin pendientes. Listo para publicar.');
}
console.log(`\n${vistos.size} landings con nombre + 1 sin nombre + la redirección de la raíz.`);
