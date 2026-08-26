/* ═══════════════════════════════════════════════════════════
   THRIVE — comportamiento compartido
   Entradas, parallax, cambio de fondo por sección, y el
   armado del mensaje de WhatsApp.
   ═══════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var CFG = window.THRIVE || {};
  var reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ───────── quién refirió ─────────
     Prioridad: lo que hornea la página (data-referida en <body>),
     luego ?de= en la URL. Si no hay ninguno, queda vacío y el
     mensaje de WhatsApp se arma sin nombre. */
  function limpiarNombre(v) {
    if (!v) return '';
    v = String(v).trim().slice(0, 40);
    return /^[\p{L}\s'.-]{2,40}$/u.test(v) ? v : '';
  }

  var referida = limpiarNombre(document.body.getAttribute('data-referida'));
  if (!referida) {
    try { referida = limpiarNombre(new URLSearchParams(location.search).get('de')); } catch (e) {}
  }

  /* ───────── mensaje de WhatsApp ─────────
     El nombre va pre-llenado a propósito: el borrador original tenía
     un espacio en blanco y la gente lo manda sin llenar. */
  /* El CTA general es para quien todavía no eligió frecuencia: no debe
     nombrar ninguna. Los botones de cada plan sí la nombran. */
  function textoWhatsApp() {
    var de = referida ? ' de parte de ' + referida : '';
    return 'Hola, Denisse! Recibí una invitación a THRIVE' + de +
           ' y me gustaría probar una clase.';
  }

  function linkWhatsApp(texto) {
    var num = (CFG.whatsapp || '').replace(/\D/g, '');
    return 'https://wa.me/' + num + '?text=' + encodeURIComponent(texto || textoWhatsApp());
  }

  /* ───────── botones de WhatsApp ─────────
     Cada plan abre su propio mensaje: si ya eligió frecuencia, Denisse
     no se lo vuelve a preguntar. El CTA general queda para quien todavía
     no sabe cuál le sirve. */
  function textoPlan(plan) {
    var de = referida ? ' de parte de ' + referida : '';
    return 'Hola, Denisse! Recibí una invitación a THRIVE' + de +
           ' y me interesa probar la opción ' + plan + '.';
  }

  document.querySelectorAll('[data-wa]').forEach(function (a) {
    var plan = a.getAttribute('data-wa-plan');
    var texto = plan ? textoPlan(plan) : (a.getAttribute('data-wa-text') || '');
    a.href = linkWhatsApp(texto);
    a.target = '_blank';
    a.rel = 'noopener';
  });

  /* ───────── entradas ─────────
     Regla dura: una visitante nunca debe ver una sección en blanco.
     Si la página no puede hacer scroll por sí misma —incrustada en un
     contenedor que crece hasta el alto del contenido— nada bajo la
     primera pantalla entraría nunca en viewport. Ahí se muestra todo. */
  var pend = [].slice.call(document.querySelectorAll('.up, .stag, .mask'));

  function mostrar(el) { el.classList.add('in'); }

  function noHaceScrollSola() {
    var d = document.scrollingElement || document.documentElement;
    return d.scrollHeight <= innerHeight + 4;
  }

  function barrer() {
    var todo = noHaceScrollSola();
    var linea = (innerHeight || 800) * 0.94;
    for (var i = pend.length - 1; i >= 0; i--) {
      var el = pend[i];
      if (el.classList.contains('in')) { pend.splice(i, 1); continue; }
      /* Basta con que haya cruzado la línea de entrada. No se exige que
         siga en pantalla: con scroll rápido, un salto de teclado o una
         posición restaurada, un bloque puede pasar de "abajo" a "arriba"
         sin aparecer nunca en un cuadro — y quedaría invisible. */
      if (todo || el.getBoundingClientRect().top < linea) { mostrar(el); pend.splice(i, 1); }
    }
  }

  if (reduced || !('IntersectionObserver' in window)) {
    pend.forEach(mostrar);
  } else if (pend.length) {
    var io = new IntersectionObserver(function (en) {
      en.forEach(function (e) {
        if (e.isIntersecting) { mostrar(e.target); io.unobserve(e.target); }
      });
    }, { threshold: 0, rootMargin: '0px 0px -8% 0px' });
    pend.forEach(function (el) { io.observe(el); });

    addEventListener('scroll', barrer, { passive: true });
    addEventListener('resize', barrer);
    addEventListener('load', barrer);
    barrer();
    [400, 1200, 2500].forEach(function (t) { setTimeout(barrer, t); });
  }

  /* ───────── el fondo cambia por sección ─────────
     También en <html>, para que el rebote de scroll de iOS no muestre
     el color de la sección anterior. */
  /* Los colores se leen del CSS, no se escriben acá. Estaban duplicados
     a mano y al cambiar la paleta quedaron desincronizados: el JS pintaba
     el crema viejo sobre el nuevo. Una sola fuente de verdad. */
  var raizCSS = getComputedStyle(document.documentElement);
  function tono(nombre, respaldo) {
    var v = raizCSS.getPropertyValue(nombre).trim();
    return v || respaldo;
  }
  var FONDOS = {
    linen: tono('--linen', '#FAF8F4'),
    sand:  tono('--sand',  '#F0EBE3'),
    ink:   tono('--ink',   '#1E1D1A')
  };
  var conFondo = [].slice.call(document.querySelectorAll('[data-ground]'));

  /* Ligado al scroll y no a un observer: gana la última sección que ya
     cruzó la mitad de la pantalla. Es determinista — con un observer,
     un scroll rápido salta secciones y el fondo se queda pegado. */
  if (!reduced && conFondo.length) {
    var ultimo = '';
    var ajustarFondo = function () {
      var medio = (innerHeight || 800) / 2;
      var elegido = conFondo[0];
      for (var k = 0; k < conFondo.length; k++) {
        if (conFondo[k].getBoundingClientRect().top <= medio) elegido = conFondo[k];
      }
      var c = FONDOS[elegido.getAttribute('data-ground')];
      if (!c || c === ultimo) return;
      ultimo = c;
      document.body.style.backgroundColor = c;
      document.documentElement.style.backgroundColor = c;
    };
    addEventListener('scroll', ajustarFondo, { passive: true });
    addEventListener('resize', ajustarFondo);
    ajustarFondo();
  }

  /* ───────── parallax ─────────
     Sutil a propósito: si se nota, está mal calibrado.
     Es lo primero que se sacrifica si hay que aligerar. */
  if (!reduced) {
    var capas = document.querySelectorAll('[data-plx]');
    if (capas.length) {
      var pidiendo = false;
      var mover = function () {
        if (pidiendo) return;
        pidiendo = true;
        requestAnimationFrame(function () {
          var vh = innerHeight;
          capas.forEach(function (el) {
            var r = el.parentElement.getBoundingClientRect();
            if (r.bottom < -80 || r.top > vh + 80) return;
            var p = (r.top + r.height / 2 - vh / 2) / vh;
            el.style.transform = 'translate3d(0,' + (p * 38).toFixed(1) + 'px,0)';
          });
          pidiendo = false;
        });
      };
      addEventListener('scroll', mover, { passive: true });
      addEventListener('resize', mover);
      mover();
    }
  }

  /* ───────── recarga en vivo, solo en local ─────────
     Vigila el CSS y el JS. Si cambian, recarga sola.
     No se activa en producción: solo en localhost. */
  if (/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    (function () {
      var vigilar = ['assets/css/thrive.css', 'assets/js/thrive.js'];
      var base = location.pathname.replace(/\/[^\/]*$/, '/');
      var raiz = base.indexOf('/i/') === 0 ? '../../' : (base === '/' ? '' : '../');
      var sello = {};
      function mirar(primera) {
        vigilar.forEach(function (f) {
          fetch(raiz + f, { method: 'HEAD', cache: 'no-store' })
            .then(function (r) {
              var t = r.headers.get('last-modified') || r.headers.get('etag') || '';
              if (primera) { sello[f] = t; return; }
              if (sello[f] && t && t !== sello[f]) location.reload();
              sello[f] = t;
            })
            .catch(function () {});
        });
      }
      mirar(true);
      setInterval(mirar, 1200);
    })();
  }

  /* ───────── expuesto para las otras páginas ───────── */
  window.THRIVE_RT = {
    referida: referida,
    linkWhatsApp: linkWhatsApp,
    textoWhatsApp: textoWhatsApp,
    limpiarNombre: limpiarNombre
  };
})();
