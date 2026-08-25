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
    enabled: false,
    url: '',            // https://xxxxx.supabase.co
    anonKey: '',        // la clave anon, nunca la service_role
    table: 'candidatas'
  },

  /* ── Las ocho clientas que reciben link ──
     slug: lo que va en la URL, en minúscula y sin tildes ni espacios.
     nombre: como aparece en el mensaje de WhatsApp.
     Al agregar o quitar a alguien acá, correr:  node build.js
     ⚠️ PENDIENTE — nombres de ejemplo, faltan los reales. */
  referidas: [
    { slug: 'margaret', nombre: 'Margaret' },
    { slug: 'isabela',  nombre: 'Isabela'  },
    { slug: 'ana',      nombre: 'Ana'      },
    { slug: 'lucia',    nombre: 'Lucía'    },
    { slug: 'carla',    nombre: 'Carla'    },
    { slug: 'sofia',    nombre: 'Sofía'    },
    { slug: 'renata',   nombre: 'Renata'   },
    { slug: 'valeria',  nombre: 'Valeria'  }
  ],

  /* ── Clase de prueba ──
     Lo que se muestra en la página de confirmación.
     ⚠️ PENDIENTE — fecha y dirección exacta de Denisse. */
  clase: {
    fecha: 'Sábado 6 de septiembre',
    hora: '7:30 a.m.',
    duracion: 60,                                  // minutos, para el calendario
    inicioISO: '2026-09-06T07:30:00-06:00',        // Honduras es UTC−6, sin horario de verano
    lugar: 'Ave. Los Próceres, Tegucigalpa',
    direccion: 'Dirección exacta pendiente',
    mapa: '',                                      // link de Google Maps
    llevar: 'Ropa cómoda, grip socks y agua.'
  },

  /* ── Estado de los cupos ──
     Al llenarse los 8, poner cuposLlenos:true y la landing pasa a
     lista de espera sin tocar el diseño. */
  cuposLlenos: false
};
