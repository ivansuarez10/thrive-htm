# THRIVE — el sitio

Sitio estático, sin framework y sin proceso de compilación. Se abre con doble clic
y se sube tal cual a cualquier hosting.

---

## Qué hay adentro

```
sitio/
  config.js               ← lo único que hay que tocar para publicar
  build.js                genera las landings desde config.js
  _template-landing.html  plantilla (no se sube al hosting)

  index.html              landing sin nombre — para redes
  i/margaret/index.html   una por clienta, con el nombre horneado
  screening/index.html    las 6 preguntas
  clase/index.html        confirmación + Google Calendar

  assets/css/thrive.css   el sistema visual completo
  assets/js/thrive.js     entradas, parallax, fondo por sección, WhatsApp
  assets/img/             fotos y logos
```

## El flujo

```
i/<clienta>/  →  WhatsApp  →  Denisse responde  →  screening/  →  clase/
   web            humano         humano             web           web
```

La landing **no termina en formulario, termina en Denisse**. El screening lo manda
ella por WhatsApp después de conversar, no antes. La confirmación reemplaza al
correo: se manda por WhatsApp y lleva el botón de calendario adentro.

## Poner a andar el sitio

**1. Editar `config.js`** — es el único archivo necesario:

- `whatsapp` — el número de Denisse en formato internacional, solo dígitos
- `referidas` — las 8 clientas, con su `slug` y su `nombre`
- `clase` — fecha, hora, dirección y link de mapa
- `baseUrl` — el dominio final

**2. Regenerar las landings** cada vez que cambien las referidas:

```bash
node build.js
```

Avisa en pantalla qué falta antes de publicar.

**3. Subir la carpeta.** No hay build ni dependencias. Funciona en Netlify,
GitHub Pages, Vercel o un hosting común. `_template-landing.html` y `build.js`
no hacen falta en el servidor, pero tampoco molestan.

## Probarlo local

```bash
python3 -m http.server 4377 --directory .
```

Y abrir `http://localhost:4377/i/margaret/`.

## Los links que manda Denisse

| Para | Link |
|---|---|
| Invitación de una clienta | `/i/margaret/` |
| Invitación sin nombre | `/` |
| Screening, tras conversar | `/screening/?de=Margaret` |
| Confirmación de la clase | `/clase/?n=Ana` |

El nombre de quien invitó viaja en el link y **pre-llena el mensaje de WhatsApp**.
El borrador original tenía un espacio en blanco: la gente lo manda sin llenar, y
justo ese es el dato que Denisse quiere.

## Guardar las respuestas del screening

Hoy `supabase.enabled` está en `false`. Con eso el formulario funciona completo,
pero **las respuestas no se guardan**: se muestran en consola y se ofrece un botón
para mandárselas a Denisse por WhatsApp. Sirve para probar el flujo sin backend.

Para encenderlo hace falta una tabla en Supabase:

```sql
create table thrive_screening (
  id             uuid primary key default gen_random_uuid(),
  referida       text,
  respuestas     jsonb not null,
  consentimiento boolean not null default false,
  enviado_en     timestamptz not null default now(),
  user_agent     text,
  estado         text not null default 'nueva'
);

alter table thrive_screening enable row level security;

-- El sitio solo inserta. Nadie puede leer con la clave pública.
create policy "insertar desde el sitio"
  on thrive_screening for insert to anon with check (true);
```

Después poner `enabled: true`, la `url` y la `anonKey` en `config.js`.

> La `anonKey` es pública y va en el navegador — es correcto.
> La `service_role` **nunca** va acá.

## Cuando se llenen los cupos

Poner `cuposLlenos: true` en `config.js`. Es un interruptor, no un rediseño.

---

## Pendientes

- **El WhatsApp de Denisse.** Hoy es `50400000000` y los botones no llevan a ningún lado.
- **Fotos reales de HTM.** Las tres actuales son de Unsplash y dicen
  *"foto de referencia"* en la página. El stock de fitness es gym duro y estética
  — justo lo que THRIVE rechaza. Sin fotos propias el posicionamiento no se sostiene.
- **Los nombres reales de las 8 clientas** en `config.js`.
- **Dirección exacta del estudio y link de Google Maps.**
- **Validar las 6 preguntas** con Denisse. Están en `screening/index.html`,
  arriba del todo, en el arreglo `PREGUNTAS`.
- **Supabase**, cuando el flujo esté aprobado.

## Tipografía

**Outfit** en titulares · **Bodoni Moda itálica** solo en acentos · **Hanken
Grotesk** en cuerpo · **DM Mono** en precios, horarios y rótulos.

El serif nunca encabeza. Aparece en tres lugares y nada más: la segunda línea del
hero, la cita del método, y el remate *living.* del titular. Es lo que mantiene el
sitio atado al logo de Denisse, que ya es una Didone. Todo se cambia desde las
variables `--display`, `--serif` y `--sans` en `assets/css/thrive.css`.

## Verificado

Probado en servidor real a 375 px y en escritorio: sin scroll horizontal, las
seis preguntas de punta a punta, el link de calendario apuntando a la hora correcta
(7:30 a.m. de Honduras = 13:30 UTC), y el mensaje de WhatsApp con el nombre puesto.

Una regla que está en el código y conviene no romper: **una visitante nunca debe
ver una sección en blanco.** Las animaciones de entrada tienen red de seguridad
para scroll rápido, saltos de teclado y páginas incrustadas.
