/* ═══════════════════════════════════════════════════════════
   THRIVE — comportamiento compartido
   Entradas, parallax, cambio de fondo por sección, y el
   armado del mensaje de WhatsApp.
   ═══════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  /* ───────── recargar devuelve al principio ─────────
     Por defecto el navegador restaura la posición de scroll al recargar,
     y acá eso rompe la puesta en escena: la apertura se anima una sola
     vez al cargar, así que quien recarga a media página cae en un tramo
     con la animación ya consumida y sin haber visto el principio. Se
     apaga la restauración y se vuelve arriba antes del primer pintado. */
  try { if ('scrollRestoration' in history) history.scrollRestoration = 'manual'; } catch (e) {}
  if (!location.hash) window.scrollTo(0, 0);

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

  /* ───────── el hero cambia de toma según la pantalla ─────────
     En el HTML viene la toma vertical, que es la del teléfono: el link
     se manda por WhatsApp, así que ese es el caso normal y tiene que
     verse aunque este archivo no llegue a ejecutarse. Acá arriba, si la
     ventana es ancha, se cambia por la horizontal.

     Se hace ANTES del bloque de video de abajo para que el observador ya
     encuentre la fuente definitiva, y solo si de verdad hay que cambiar:
     tocar src sin necesidad reinicia la descarga. */
  (function () {
    var v = document.querySelector('[data-hero] video[data-ancho]');
    if (!v || !window.matchMedia || !matchMedia('(min-width: 900px)').matches) return;

    var fuente = v.querySelector('source');
    if (fuente) fuente.setAttribute('src', v.getAttribute('data-ancho'));
    var poster = v.getAttribute('data-ancho-poster');
    if (poster) {
      v.setAttribute('poster', poster);
      var fija = v.parentNode.querySelector('img.poster');
      if (fija) fija.setAttribute('src', poster);
    }
    v.load();

    /* Y se arranca acá mismo. Dejarlo en manos del observador de abajo
       es frágil: load() reinicia el elemento y la promesa de play() puede
       quedar cancelada por esa misma recarga. Si el navegador no lo deja
       todavía, el intento se repite en cuanto haya datos. */
    var arrancar = function () {
      v.muted = true;
      var p = v.play();
      if (p && p.catch) p.catch(function () {});
    };
    arrancar();
    v.addEventListener('canplay', arrancar, { once: true });
  })();

  /* ───────── los videos de fondo ─────────
     Son fotos que se mueven, no reproductores: nunca deben mostrar un
     botón de play. `autoplay muted playsinline` debería bastar y no
     basta — el navegador puede negarse por batería, por datos, o porque
     la pestaña nació en segundo plano.

     La estrategia es insistir y, si igual se niega, disimular:

     1. `muted` se pone como PROPIEDAD y no solo como atributo. Safari
        mira la propiedad en el momento de play(), y no siempre coinciden.
     2. Se arrancan al entrar en pantalla y se pausan al salir, para no
        gastar batería ni datos fuera de vista.
     3. Si play() se rechaza, el video queda anotado y se reintenta con
        el primer gesto de la visitante y cada vez que la pestaña vuelve
        al frente: casi todos los bloqueos se levantan ahí.
     4. Lo que no se levanta con nada es el **Modo de bajo consumo de
        iOS**. A los 3 segundos se acepta la derrota y se cambia el video
        por su poster —una foto fija, que se ve deliberada— en vez de
        dejar el botón de play, que se ve roto.

     Quien pidió menos movimiento no ve video: el CSS lo oculta. */
  (function () {
    var videos = [].slice.call(document.querySelectorAll('video[data-plx], .band video'));
    if (!videos.length) return;

    if (reduced) {
      videos.forEach(function (v) { try { v.pause(); v.removeAttribute('autoplay'); } catch (e) {} });
      return;
    }

    /* Los que alguna vez se negaron. No se vacía al rendirse: si más
       tarde la visitante toca la pantalla, se les vuelve a dar. */
    var caidos = [];

    function anotar(v) { if (caidos.indexOf(v) < 0) caidos.push(v); }

    function intentar(v) {
      try {
        v.muted = true;
        v.defaultMuted = true;
        v.playsInline = true;
      } catch (e) {}

      var p;
      try { p = v.play(); } catch (e) { anotar(v); return; }
      if (!p || !p.then) return;

      p.then(function () {
        v.classList.remove('sin-auto');
        var k = caidos.indexOf(v);
        if (k >= 0) caidos.splice(k, 1);
      }).catch(function () { anotar(v); });
    }

    function reintentar() {
      caidos.slice().forEach(intentar);
    }

    /* Un gesto levanta casi todo. No se usa `once`: el Modo de bajo
       consumo puede apagarse a mitad de la visita y ahí sí arranca. */
    ['pointerdown', 'touchstart', 'keydown'].forEach(function (ev) {
      addEventListener(ev, reintentar, { passive: true });
    });
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') reintentar();
    });

    /* La derrota, a los 3 s: el poster ocupa el lugar del video. */
    setTimeout(function () {
      caidos.forEach(function (v) { v.classList.add('sin-auto'); });
    }, 3000);

    if (!('IntersectionObserver' in window)) { videos.forEach(intentar); return; }

    var obs = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (e) {
        if (e.isIntersecting) intentar(e.target);
        else { try { e.target.pause(); } catch (err) {} }
      });
    }, { rootMargin: '200px 0px', threshold: 0.01 });

    videos.forEach(function (v) { obs.observe(v); });
  })();

  /* ───────── entradas, en las dos direcciones ─────────
     Los bloques entran al aparecer y se vuelven a esconder al salir, y
     regresan desde el lado por el que se fueron: si bajás vienen desde
     abajo, si subís vienen desde arriba.

     Regla dura del proyecto que sigue mandando: una visitante nunca debe
     ver una sección en blanco. Por eso hay tres salidas de emergencia —
     sin IntersectionObserver, sin scroll propio, o si el observador
     nunca llegó a disparar— y en las tres se muestra todo y se deja
     quieto para siempre. */
  var pend = [].slice.call(document.querySelectorAll('.up, .stag, .mask'));

  function mostrarTodoYFijar() {
    document.body.classList.remove('dosvias');
    pend.forEach(function (el) { el.classList.add('in'); el.classList.remove('desde-arriba'); });
  }

  /* No se pregunta si la página hace scroll: al primer pintado todavía
     no cargaron fuentes ni imágenes, la página es corta, y apagar el
     modo ahí lo apagaba para siempre. El observador resuelve ese caso
     solo — si todo cabe en pantalla, todo intersecta y todo se revela. */
  if (reduced || !('IntersectionObserver' in window) || !pend.length) {
    mostrarTodoYFijar();
  } else {
    document.body.classList.add('dosvias');
    var algunoEntro = false;

    var io = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (e) {
        var el = e.target;
        if (e.isIntersecting) {
          algunoEntro = true;
          el.classList.add('in');
        } else {
          /* de qué lado se fue decide de qué lado vuelve */
          el.classList.toggle('desde-arriba', e.boundingClientRect.top < 0);
          el.classList.remove('in');
        }
      });
    }, { threshold: 0, rootMargin: '0px 0px -8% 0px' });

    pend.forEach(function (el) { io.observe(el); });

    /* Tercera salida: si el observador no marca ni un bloque, algo lo
       bloqueó y la página quedaría en blanco. Se abandona el modo.

       Pero el reloj solo corre con la pestaña a la vista. Un link de
       WhatsApp puede abrirse en segundo plano, y ahí el observador no
       dispara por diseño, no por falla: contar ese tiempo apagaría el
       efecto antes de que nadie llegue a mirar la página. */
    var reloj = null;
    function armarRelojDeSeguridad() {
      if (document.visibilityState !== 'visible' || reloj || algunoEntro) return;
      reloj = setTimeout(function () {
        if (!algunoEntro) { io.disconnect(); mostrarTodoYFijar(); }
      }, 2500);
    }
    armarRelojDeSeguridad();
    document.addEventListener('visibilitychange', armarRelojDeSeguridad);

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
  /* Sin el gate de `reduced` a propósito, y esto es un arreglo, no un
     descuido que se hereda: apagarlo dejaba la landing ENTERA blanca para
     quien pide menos movimiento —data-ground no tiene una sola línea de
     CSS, el color vive solo acá—, y con eso las secciones `sand` perdían
     su separación y las tarjetas de plan quedaban blancas sobre blanco,
     que es justo la trampa anotada arriba en --linen.

     Un color de fondo NO es movimiento: no marea a nadie. Lo que hay que
     quitar es el viaje de 900 ms, y de eso ya se encarga el CSS con
     body{transition:none} dentro de prefers-reduced-motion. O sea que el
     color cambia igual, pero al instante.

     ⚠️ Lo que NO sirve: darle fondo propio a cada sección en CSS.
     section{position:relative}, así que una sección con fondo TAPA
     body::before — el degradado de arcilla que es toda la calidez del
     sitio desde que la página pasó a blanco. */
  if (conFondo.length) {
    var ultimo = '';
    /* Envuelto en rAF como el parallax y el riel de capacidades: era el
       único de los tres escuchas de scroll que corría sincrónico, y hacía
       un getBoundingClientRect() por sección en cada evento.

       ⚠️ Acá el cerrojo booleano SÍ es correcto, al revés que en el riel
       —donde un cuadro que no llega lo deja trabado en true para siempre—.
       La diferencia es que el riel también se llama desde visibilitychange
       para recalcular al volver a la pestaña; este se llama desde scroll y
       resize, y no hay scroll con la pestaña oculta. Si algún día se le
       agrega un visibilitychange, hay que pasarlo al patrón de
       cancelAnimationFrame del riel. */
    var cuadroFondo = 0;
    var pintarFondo = function () {
      cuadroFondo = 0;
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
    var ajustarFondo = function () {
      if (cuadroFondo) return;
      cuadroFondo = requestAnimationFrame(pintarFondo);
    };
    addEventListener('scroll', ajustarFondo, { passive: true });
    addEventListener('resize', ajustarFondo);
    /* La primera pasada va DIRECTA, sin rAF. Un link de WhatsApp puede
       abrirse en segundo plano, y con la pestaña oculta el navegador no
       entrega cuadros: encolar la pintura inicial la dejaría esperando
       hasta el primer scroll. Hoy la primera sección es `linen`, que es
       el fondo por defecto, así que no se vería — pero eso es suerte del
       orden de las secciones, no una garantía. */
    pintarFondo();
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

  /* ───────── el riel de capacidades ─────────
     Las seis palabras del margen aparecen una por una a medida que se
     baja. No es un escalonado que se dispara al entrar: está atado a la
     posición del scroll, así que si se sube, se vuelven a apagar. Eso es
     lo que pidió Ivan — «que aparezcan según hago scroll».

     Se cuelga del mismo patrón que el parallax —un rAF por cuadro y el
     escucha en modo pasivo— para no agregar un segundo bucle de scroll.

     Los umbrales van de .06 a .76 y no de 0 a 1: la última palabra tiene
     que encenderse ANTES de que la sección empiece a irse, o nunca se la
     ve completa. */
  if (!reduced) {
    var rieles = [].slice.call(document.querySelectorAll('[data-capacidades]'));
    if (rieles.length) {
      /* Recién acá se apagan. El CSS las deja VISIBLES por defecto: si
         este script no llega, el pie de la sección se lee igual. */
      document.body.classList.add('capacidades-vivas');

      /* Se guarda el número de cuadro en vez de un booleano, y cada
         llamada CANCELA el anterior y pide uno nuevo.

         Con un booleano —`if (pidiendo) return; pidiendo = true;`— basta
         con que un cuadro no llegue para que el cerrojo quede trabado en
         true y la función muera para siempre. Pasa de verdad: mientras la
         pestaña está oculta el navegador deja de dar cuadros. Así se
         repara solo, y al volver a la pestaña el cuadro pendiente corre. */
      var cuadro = 0;

      var llenar = function () {
        if (cuadro) cancelAnimationFrame(cuadro);
        cuadro = requestAnimationFrame(function () {
          cuadro = 0;
          var vh = innerHeight;
          rieles.forEach(function (riel) {
            var palabras = riel.children;
            var n = palabras.length;
            if (!n) return;

            /* Se mide contra LA PROPIA TIRA, no contra la sección.

               Medir la sección era lo correcto cuando el riel era un lomo
               vertical que ocupaba sus 1364 px de alto y estaba en pantalla
               todo el rato. Acostado como pie, la tira mide 30 px: con el
               recorrido atado a la sección, cuando se iba por arriba el
               avance recién iba por .46 y sólo se habían encendido TRES de
               las seis. Se veía como que no terminaban de cargar, y era eso.

               Ahora: 0 cuando su tope entra por abajo (92 % del alto), 1
               media pantalla después. Se llena entera MIENTRAS se la ve y
               cierra la sección justo al terminar de leerla. */
            var r = riel.getBoundingClientRect();
            var avance = (vh * 0.92 - r.top) / Math.max(vh * 0.45, 1);
            if (avance < 0) avance = 0;
            if (avance > 1) avance = 1;

            for (var i = 0; i < n; i++) {
              var umbral = 0.06 + (i / (n - 1 || 1)) * 0.70;
              palabras[i].classList.toggle('vista', avance >= umbral);
            }
          });
        });
      };

      /* ⚠️ El escucha va en DOCUMENT y en fase de CAPTURA, no en window.
         En este sitio quien hace scroll es el <body> (lleva overflow), y
         el evento scroll de un contenedor NO burbujea hasta la ventana:
         colgado de window no se disparaba nunca y el riel se quedaba
         apagado para siempre. En captura sí lo ve, venga del body, del
         documento o de cualquier caja con scroll propio. */
      /* En captura y sobre document: así vale igual si algún día el scroll
         lo lleva el documento o una caja con overflow propio. */
      document.addEventListener('scroll', llenar, { passive: true, capture: true });
      addEventListener('resize', llenar);
      /* Al volver a la pestaña se recalcula: mientras estuvo oculta pudo
         moverse el scroll sin que llegara un solo cuadro. */
      document.addEventListener('visibilitychange', function () {
        if (!document.hidden) llenar();
      });
      llenar();
    }
  }

  /* ───────── recarga en vivo, solo en local ─────────
     Vigila el CSS y el JS. Si cambian, recarga sola.
     No se activa en producción: solo en localhost. */
  if (/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    (function () {
      /* ⚠️ Rutas ABSOLUTAS, como todo lo demás del sitio. Antes se
         calculaba un '../' contando niveles, y con eso el vigilante
         pedía /thrive/assets/... desde /thrive/form/: 404 cada 1.2 s,
         para siempre. Dos consecuencias — la recarga en vivo nunca
         funcionó en el formulario ni en el pase, y la consola quedaba
         tan llena de 404 que tapaba los errores de verdad. */
      var vigilar = ['/assets/css/thrive.css', '/assets/js/thrive.js'];
      var sello = {};
      function mirar(primera) {
        vigilar.forEach(function (f) {
          fetch(f, { method: 'HEAD', cache: 'no-store' })
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

  /* ───────── la luz responde a quien mira ─────────
     El detalle de por qué se mueve con transform, por qué la capa va
     inflada y por qué el grano NO se mueve está en thrive.css, junto a
     la regla. Acá vive solo el cálculo.

     AMPLITUD chica a propósito: 18 px sobre un degradado de 120vmax es
     cerca del 1 %. Si hay que subirla hasta que se note claramente, ya se
     notó demasiado — deja de ser luz y se vuelve efecto.

     SIGNO negativo = parallax: la luz se aleja del cursor. Es lo que la
     mantiene siendo una ventana. Para que persiga al mouse, quitar el
     menos de AMPLITUD y nada más. */
  if (!reduced && matchMedia('(hover:hover) and (pointer:fine)').matches) {
    (function () {
      var AMPLITUD = -18;
      var raizEl = document.documentElement;
      var dx = 0, dy = 0, tx = 0, ty = 0, corriendo = false;

      /* Persecución con retraso: .055 por cuadro. Sin retraso la luz
         queda pegada al cursor y delata el truco; con retraso tiene masa.
         El bucle se apaga solo al llegar —no hay rAF eterno de fondo. */
      function seguir() {
        tx += (dx - tx) * .055;
        ty += (dy - ty) * .055;
        raizEl.style.setProperty('--luz-x', tx.toFixed(2) + 'px');
        raizEl.style.setProperty('--luz-y', ty.toFixed(2) + 'px');
        if (Math.abs(dx - tx) > .08 || Math.abs(dy - ty) > .08) requestAnimationFrame(seguir);
        else corriendo = false;
      }

      addEventListener('mousemove', function (e) {
        dx = (e.clientX / innerWidth  - .5) * 2 * AMPLITUD;
        dy = (e.clientY / innerHeight - .5) * 2 * AMPLITUD;
        if (!corriendo) { corriendo = true; requestAnimationFrame(seguir); }
      }, { passive: true });
    })();
  }

  /* ───────── el sello de la portada responde al scroll ─────────
     El sello entra letra por letra al cargar —eso lo hace el CSS con los
     mismos keyframes del formulario— y a partir de ahí sigue al scroll:
     el anillo gira doce grados, el conjunto sube un poco y se apaga
     mientras la portada se va. Decisión de Ivan, 27 ago 2026.

     Se escribe UNA variable, --pa, de 0 a 1. El CSS la usa solo en
     transform y opacity, así que el navegador lo resuelve en el
     compositor: no hay una sola maquetación de más por cuadro.

     Nada de esto es necesario para que la página funcione. Si este
     bloque no corre, --pa se queda en 0, el sello queda puesto y la
     portada se scrollea como cualquier sección. */
  if (!reduced) {
    (function () {
      var sello = document.querySelector('.portada-sello');
      var portada = document.getElementById('portada');
      if (!sello || !portada) return;

      var cuadro = 0;
      var pintar = function () {
        cuadro = 0;
        var alto = portada.offsetHeight || innerHeight;
        /* Cuánto de la portada ya se fue por arriba. Se mide contra su
           propio alto y no contra la ventana: así vale igual en un
           teléfono apaisado que en un monitor alto. */
        var pa = -portada.getBoundingClientRect().top / alto;
        if (pa < 0) pa = 0;
        if (pa > 1) pa = 1;
        sello.style.setProperty('--pa', pa.toFixed(4));
      };

      /* Se cancela el cuadro anterior y se pide uno nuevo, en vez de un
         cerrojo booleano: si un cuadro no llega —pestaña oculta— el
         cerrojo quedaría trabado y el sello no volvería a moverse nunca.
         Misma forma que el riel de capacidades. */
      var pedir = function () {
        if (cuadro) cancelAnimationFrame(cuadro);
        cuadro = requestAnimationFrame(pintar);
      };

      addEventListener('scroll', pedir, { passive: true });
      addEventListener('resize', pedir);
      pintar();
    })();
  }

  /* ───────── del precio al pie, sin perder el plan ─────────
     Los botones de cada plan bajan a la sección de invitación en vez de
     ir derecho al formulario: ese bloque dice «antes de comprometerte,
     quiero que vengás a vivir la experiencia», y saltárselo era mandar a
     alguien del precio al cuestionario sin haberle contado la clase de
     prueba.

     Lo que se recuerda es el PLAN. Sin esto, elegir 2X y bajar dejaba a
     Denisse sin saber cuál eligió —el dato con el que arma los grupos—.

     El ancla del href hace el trabajo aunque el JS no llegue: baja igual
     y el botón de abajo manda al formulario sin plan, que es exactamente
     como funcionaba antes. Nada depende de este bloque para funcionar. */
  (function () {
    var botones = [].slice.call(document.querySelectorAll('[data-plan-cta]'));
    var final = document.querySelector('[data-cta-final]');
    if (!botones.length || !final) return;

    var baseFinal = final.getAttribute('href');

    botones.forEach(function (b) {
      b.addEventListener('click', function () {
        var plan = b.getAttribute('data-plan-cta');
        if (!/^[23]X$/.test(plan)) return;          /* solo lo que conocemos */

        /* ⚠️ El hash se BORRA de la URL apenas cumplió su trabajo.
           Sin esto, la direccion queda en …/thrive/#invitacion — y como
           esa seccion esta al 98 % del documento, el proximo refresco
           tiraba a la persona casi al final de la pagina. Ivan lo
           encontro en el telefono el 27 ago 2026.

           Se usa replaceState y no location.hash='' porque asignar el
           hash vacio deja el '#' colgando y agrega una entrada al
           historial: el boton de atras dejaria de servir.

           El href del boton NO se toca: sigue siendo #invitacion, que es
           lo que hace bajar cuando el JS no llega. La limpieza pasa
           despues del salto, no en vez de el. */
        setTimeout(function () {
          try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
        }, 0);
        final.setAttribute('href', baseFinal + '?plan=' + plan);
        /* El texto del botón también lo dice: si alguien baja y ve
           «Quiero probar THRIVE» a secas, no tiene forma de saber que su
           elección viajó con él. */
        var t = final.firstChild;
        if (t && t.nodeType === 3) t.nodeValue = '\n        Quiero probar THRIVE ' + plan + '\n        ';
      });
    });
  })();

  /* ───────── expuesto para las otras páginas ───────── */
  window.THRIVE_RT = {
    referida: referida,
    linkWhatsApp: linkWhatsApp,
    textoWhatsApp: textoWhatsApp,
    limpiarNombre: limpiarNombre
  };
})();
