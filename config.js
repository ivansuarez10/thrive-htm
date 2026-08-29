/* ═══════════════════════════════════════════════════════════
   THRIVE — configuración del sitio
   Este es el único archivo que hay que tocar para poner el
   sitio en producción. Todo lo demás lee de acá.
   ═══════════════════════════════════════════════════════════ */

window.THRIVE = {

  /* ── WhatsApp de Denisse ──
     Formato internacional, solo dígitos, sin + ni espacios.
     Honduras es 504. Ejemplo: 50499887766
     WhatsApp Business de Denisse, confirmado el 25 ago 2026. */
  whatsapp: '50488912039',

  /* ── Dónde vive el sitio ──
     Sin barra al final. Se usa para armar los links que Denisse manda.
     ⚠️ OJO: healingthroughmovement.COM es de otra empresa, no de HTM.
     El dominio de Denisse es el .studio. No confundirlos. */
  baseUrl: 'https://healingthroughmovement.studio',

  /* ── Supabase ──
     Mientras esté apagado, el formulario funciona completo pero las
     respuestas no se guardan: se muestran en consola y se ofrece
     mandarlas por WhatsApp. Sirve para probar el flujo sin backend.

     Para encenderlo:
       1. Correr sitio/supabase/schema.sql en el SQL Editor
       2. Pegar acá la URL y la clave anon (Settings → API)
       3. enabled: true

     La clave anon es PÚBLICA por diseño y va en el navegador. Lo que
     protege los datos son las políticas RLS del schema, no la clave.
     Nunca pegar acá la service_role. */
  supabase: {
    enabled: true,
    url: 'https://cbdnbzkoorzeezcgzziu.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNiZG5iemtvb3J6ZWV6Y2d6eml1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2OTI3NzcsImV4cCI6MjEwMzI2ODc3N30.hlXuI2E-ShTjrgHrm5X1X5vxoxoDDTaWz-r_EU-K61g',
    table: 'candidatas'
  },

  /* ── El link de invitación ──
     DECISIÓN del 26 ago 2026: el link es UNO SOLO y sin personalizar.
     Denisse comparte https://healingthroughmovement.studio/thrive y ya.

     Antes esta lista horneaba una landing por clienta (/thrive/ana) para
     que el mensaje de WhatsApp saliera con «de parte de Ana». Se apagó
     porque **la pregunta 3 del cuestionario ya captura quién la
     recomendó**, que era el dato que se quería. Un link general es una
     cosa menos que mantener y una menos que equivocar.

     La maquinaria NO se borró, solo se dejó vacía: si algún día se
     quieren links por persona, se vuelven a poner acá y `node build.js`
     los hornea de nuevo. Y el soporte de ?de=Ana en la URL sigue vivo en
     thrive.js, así que un link personalizado suelto funciona sin
     necesidad de horneado.

     Al vaciar esta lista, build.js barre las carpetas de las clientas
     que ya no están. Eso es lo que se quiere. */
  referidas: [],

  /* ⚠️ `cuposPrueba` se quitó el 29 ago 2026. Las cuatro fechas de clase
     de prueba viven AHORA en la base, en programas.ajustes.slots, que es
     lo que lee el panel y lo que Denisse edita desde Ajustes. Tenerlas
     también acá era pedir que un día se contradigan, y a seis días de la
     primera clase esa contradicción se paga cara.
     Si hace falta verlas: panel → Ajustes → Clases de prueba. */


  /* ── Clase de prueba ──
     Lo que se muestra en la página de confirmación.
     ⚠️ PENDIENTE — la FECHA de la clase de prueba sigue siendo de relleno. */
  clase: {
    /* ⚠️ LA FECHA YA NO VIVE ACÁ (26 ago 2026).
       Denisse le asigna la clase de prueba a cada clienta a mano desde el
       panel, y el link del pase lleva SU fecha adentro (?d=…). La página
       de confirmación NO lee 'fecha', 'hora', 'inicioISO' ni
       'fechaConfirmada': sin fecha en el link dice que falta, en vez de
       mostrarle a alguien la fecha de otra.

       Se dejan escritos porque son el registro de lo último que se habló
       —dos días de prueba, de fin de semana— y porque borrarlos ahora
       rompería cualquier página que todavía los lea. No son la verdad de
       nadie: la verdad es 'clase_en' de cada candidata, en la base. */
    fechaConfirmada: false,
    fecha: 'Sábado 6 de septiembre',
    hora: '7:30 a.m.',
    duracion: 60,                                  // minutos, para el calendario
    inicioISO: '2026-09-06T07:30:00-06:00',        // Honduras es UTC−6, sin horario de verano
    lugar: 'Healing Through Movement · Ave. Los Próceres, Tegucigalpa',
    /* De la ficha verificada de Google Maps. Se confirmó que es la de
       Denisse y no un homónimo porque el teléfono de la ficha (8891-2039)
       es el mismo WhatsApp del sitio. */
    direccion: 'Av. Los Próceres, Tegucigalpa 11101, Francisco Morazán',
    /* ⚠️ Cambiado el 29 ago 2026: Denisse reportó que el link abría Google
       Maps pero no marcaba la ubicación. El anterior era una URL de tipo
       /place/ con nombre y coordenadas pero SIN identificador del lugar, y
       cuando el nombre no calza exacto Google cae al mapa centrado, sin pin.

       Este usa la API de búsqueda con las coordenadas: cae un pin exacto,
       siempre, sin depender de que Google reconozca el nombre.

       Lo que se pierde: no abre la ficha del negocio con reseñas y horarios.
       Para eso hace falta el link de «Compartir» de la ficha de Denisse en
       Google Maps, que lo tiene que sacar ella de su cuenta. */
    mapa: 'https://www.google.com/maps/search/?api=1&query=14.1024003%2C-87.1808674',
    /* Lo que va en el campo 'ubicación' de Google Calendar. Tiene que ser
       geocodificable: nombre del negocio + dirección, sin separadores
       decorativos. Si se arma juntando 'lugar' y 'direccion' sale la
       avenida repetida y un '·' que Google no interpreta, y el evento
       queda sin pin. */
    direccionCalendario: 'Healing Through Movement by Denisse Suazo, Av. Los Próceres, Tegucigalpa 11101, Honduras',
    /* «Y vení con toda tu energía» se quitó a pedido de Denisse (29 ago
       2026): pone una condición de ánimo para poder participar, y THRIVE
       está construido justo al revés — no hace falta llegar perfecta,
       descansada ni con energía para entrenar. */
    llevar: 'Traé ropa cómoda, toalla, grip socks y tu botella con agua. Del resto nos encargamos acá.'
  },

  /* ── Estado de los cupos ──
     Al llenarse los 8, poner cuposLlenos:true y la landing pasa a
     lista de espera sin tocar el diseño. */
  cuposLlenos: false
};
