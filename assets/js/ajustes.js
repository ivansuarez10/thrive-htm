/* ═══════════════════════════════════════════════════════════
   THRIVE — los ajustes que Denisse edita, leídos por el sitio

   Denisse cambia precios, horarios, cupos y dirección desde
   /panel → Ajustes, y eso se guarda en la base. Este archivo es
   el otro extremo del cable: trae esos valores y los deja encima
   de window.THRIVE, de modo que TODA página que ya lee
   window.THRIVE los recibe sin cambiar una línea más.

   ── Cómo se enchufa ──
   En cada página, DESPUÉS de config.js y ANTES del script que la
   pinta:

     <script src="/config.js"></script>
     <script src="/assets/js/ajustes.js"></script>
     <script>
       THRIVE_AJUSTES.listo(function(){
         // acá pintar. window.THRIVE ya trae lo de la base.
       });
     </script>

   ── Por qué así y no de otra forma ──
   El sitio es estático y vive en GitHub Pages. No hay servidor que
   pueda hornear estos valores en el HTML, así que o los pide el
   navegador o no los tiene. Pedirlos tiene un costo: un viaje de
   red antes de pintar.

   Por eso config.js NO se borra y NO es un respaldo de emergencia:
   es lo que la página muestra mientras la red contesta, y lo que
   muestra para siempre si la red no contesta. Una landing que
   depende de una consulta para decir su precio es una landing que
   a veces no dice su precio.
   ═══════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var CFG = (window.THRIVE && window.THRIVE.supabase) || {};
  var esperando = [];
  var resuelto = false;

  function terminar() {
    if (resuelto) return;
    resuelto = true;
    var cola = esperando;
    esperando = [];
    cola.forEach(function (fn) {
      try { fn(); } catch (e) { console.error(e); }
    });
  }

  window.THRIVE_AJUSTES = {
    /* Corre fn cuando los ajustes ya llegaron —o cuando quedó claro
       que no van a llegar—. Nunca se queda esperando para siempre:
       una página que no pinta es peor que una con precios viejos. */
    listo: function (fn) {
      if (resuelto) { fn(); return; }
      esperando.push(fn);
    }
  };

  if (!CFG.enabled || !CFG.url || !CFG.anonKey) { terminar(); return; }

  /* Se consulta la VISTA, no la tabla. `ajustes` tiene una columna
     que es solo del panel (`panel_visto_en`) y la clave pública no
     tiene permiso para leerla: pedir la tabla entera devuelve 42501
     y la página se queda sin nada. La vista expone exactamente lo
     que el sitio necesita. */
  var url = CFG.url.replace(/\/$/, '') + '/rest/v1/ajustes_publicos?select=*&limit=1';

  /* Un límite de tiempo, porque no hay nada que valga la pena
     esperar más que esto antes de pintar una página. */
  var reloj = setTimeout(terminar, 2500);

  fetch(url, {
    headers: { apikey: CFG.anonKey, Authorization: 'Bearer ' + CFG.anonKey },
    cache: 'no-store'
  })
    .then(function (r) { return r.ok ? r.json() : []; })
    .then(function (filas) {
      var a = filas && filas[0];
      if (!a) return;

      var T = window.THRIVE = window.THRIVE || {};
      T.clase = T.clase || {};

      /* Solo pisa lo que la base tiene lleno. Un campo en null
         significa «Denisse no lo ha tocado», no «bórralo»: si no,
         estrenar la pantalla de Ajustes vaciaría la landing. */
      function poner(destino, llave, valor) {
        if (valor === null || valor === undefined || valor === '') return;
        destino[llave] = valor;
      }

      poner(T, 'whatsapp', a.whatsapp);
      poner(T.clase, 'hora', a.hora);
      poner(T.clase, 'direccion', a.direccion);
      poner(T.clase, 'mapa', a.mapa);

      T.programa = T.programa || {};
      poner(T.programa, 'precio2X', a.precio_2x);
      poner(T.programa, 'precio3X', a.precio_3x);
      poner(T.programa, 'dias2X', a.dias_2x);
      poner(T.programa, 'dias3X', a.dias_3x);
      poner(T.programa, 'cupos', a.cupos_por_grupo);
      poner(T.programa, 'inicio', a.periodo_inicio);
      poner(T.programa, 'fin', a.periodo_fin);
    })
    .catch(function (e) { console.warn('ajustes:', e && e.message); })
    .then(function () { clearTimeout(reloj); terminar(); });
})();
