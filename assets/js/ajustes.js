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
  var base = CFG.url.replace(/\/$/, '') + '/rest/v1/';
  var cab  = { apikey: CFG.anonKey, Authorization: 'Bearer ' + CFG.anonKey };

  /* Un límite de tiempo, porque no hay nada que valga la pena esperar
     más que esto antes de pintar una página. */
  var reloj = setTimeout(terminar, 2500);

  function traer(q){
    return fetch(base + q, { headers: cab, cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : []; })
      .catch(function () { return []; });
  }

  /* Solo pisa lo que la base tiene lleno. Un campo en null significa
     «Denisse no lo ha tocado», no «bórralo»: si no, estrenar la pantalla
     de Ajustes vaciaría la landing. */
  function poner(destino, llave, valor) {
    if (valor === null || valor === undefined || valor === '') return;
    destino[llave] = valor;
  }

  Promise.all([
    /* Lo de Denisse: WhatsApp, dirección, mapa. */
    traer('ajustes_publicos?select=*&limit=1'),
    /* Y lo del programa. Los precios y horarios se mudaron acá el 27 de
       agosto —uno por programa— y `ajustes_publicos` se quedó con esas
       columnas en NULL, que es la peor forma de quedar obsoleta: no
       falla, devuelve nada. */
    traer('programas_publicos?select=*&id=eq.thrive&limit=1')
  ]).then(function (r) {
    var a = r[0] && r[0][0];
    var p = r[1] && r[1][0];
    var T = window.THRIVE = window.THRIVE || {};
    T.clase = T.clase || {};
    T.programa = T.programa || {};

    if (a) {
      poner(T, 'whatsapp', a.whatsapp);
      poner(T.clase, 'direccion', a.direccion);
      poner(T.clase, 'mapa', a.mapa);
    }

    if (p) {
      poner(T.clase, 'hora', p.hora);
      poner(T.programa, 'hora', p.hora);
      poner(T.programa, 'cupos', p.cupos_por_grupo);
      poner(T.programa, 'inicio', p.periodo_inicio);
      poner(T.programa, 'fin', p.periodo_fin);
      (p.grupos || []).forEach(function (g) {
        if (!g || !g.id) return;
        poner(T.programa, 'precio' + g.id, g.precio);
        poner(T.programa, 'dias' + g.id, g.dias);
      });
    }

    pintar(T);
  }).catch(function (e) {
    console.warn('ajustes:', e && e.message);
  }).then(function () {
    clearTimeout(reloj);
    terminar();
  });

  /* ═══ y ahora se escribe en la página ═══
     Con atributos data-aj en vez de tocar el HTML de cada página: así
     esto no sabe nada de la estructura de la landing y la landing no
     sabe nada de la base. El valor que ya está impreso —el de
     config.js— es lo que se ve mientras viaja la consulta, y lo que se
     queda si la consulta no llega. Una landing que depende de la red
     para decir su precio es una landing que a veces no dice su precio. */
  function pintar(T) {
    var mapa = {
      'whatsapp'  : T.whatsapp,
      'hora'      : T.programa.hora || T.clase.hora,
      'cupos'     : T.programa.cupos,
      'direccion' : T.clase.direccion,
      'precio2X'  : T.programa.precio2X != null ? '$' + T.programa.precio2X : null,
      'precio3X'  : T.programa.precio3X != null ? '$' + T.programa.precio3X : null,
      'dias2X'    : T.programa.dias2X,
      'dias3X'    : T.programa.dias3X
    };
    document.querySelectorAll('[data-aj]').forEach(function (el) {
      var v = mapa[el.getAttribute('data-aj')];
      if (v === null || v === undefined || v === '') return;
      if (String(el.textContent).trim() === String(v).trim()) return;
      el.textContent = v;
    });
  }
})();
