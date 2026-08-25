# THRIVE — el sitio

Sitio estático, sin framework y sin proceso de compilación.

Vive en **healingthroughmovement.studio**, el dominio de HTM. Como el sitio ocupa
el dominio completo, los assets se referencian desde la raíz (`/assets/…`). Eso
significa que **ya no se abre con doble clic**: hay que servirlo (ver *Probarlo
local*). A cambio, ninguna página se rompe por estar más adentro en el árbol.

> ⚠️ `healingthroughmovement.com` **no es de HTM** — es de otra empresa. El dominio
> de Denisse es el `.studio`. No confundirlos en ningún link.

---

## Qué hay adentro

```
sitio/
  config.js               ← lo único que hay que tocar para publicar
  build.js                genera las landings desde config.js
  _template-landing.html  plantilla (no se sube al hosting)

  CNAME                   el dominio, para GitHub Pages

  index.html              redirección de la raíz a /thrive/   ← generado
  thrive/index.html       landing sin nombre — para redes     ← generado
  thrive/margaret/        una por clienta, con el nombre      ← generado
  thrive/form/            las 6 preguntas
  thrive/schedule/        confirmación + Google Calendar

  assets/css/thrive.css   el sistema visual completo
  assets/js/thrive.js     entradas, parallax, fondo por sección, WhatsApp
  assets/img/             fotos y logos
```

## El flujo

```
/thrive/<clienta>  →  WhatsApp  →  Denisse responde  →  /thrive/form  →  /thrive/schedule
       web              humano          humano                web                web
```

La landing **no termina en formulario, termina en Denisse**. El screening lo manda
ella por WhatsApp después de conversar, no antes. La confirmación reemplaza al
correo: se manda por WhatsApp y lleva el botón de calendario adentro.

## Poner a andar el sitio

**1. Editar `config.js`** — es el único archivo necesario:

- `whatsapp` — el número de Denisse en formato internacional, solo dígitos
- `referidas` — las 8 clientas, con su `slug` y su `nombre`
- `clase` — fecha, hora, dirección y link de mapa
- `baseUrl` — el dominio final (`https://healingthroughmovement.studio`)

**2. Regenerar las landings** cada vez que cambien las referidas:

```bash
node build.js
```

Avisa en pantalla qué falta antes de publicar.

**3. `git push`.** GitHub Pages reconstruye solo en un par de minutos.
`_template-landing.html` y `build.js` no hacen falta en el servidor, pero tampoco
molestan. El archivo `CNAME` sí: es lo que amarra el dominio, no lo borres.

Ojo: las páginas se sirven desde la raíz del dominio. Si algún día esto se moviera
a un subdirectorio, las rutas `/assets/…` se rompen todas.

## Probarlo local

```bash
python3 -m http.server 4377 --directory .
```

Y abrir `http://localhost:4377/thrive/margaret/`. **Tiene que servirse desde la
raíz de `sitio/`** — si se sirve desde más adentro, `/assets/…` no resuelve.

## Los links que manda Denisse

| Para | Link |
|---|---|
| Invitación de una clienta | `healingthroughmovement.studio/thrive/margaret` |
| Invitación sin nombre | `healingthroughmovement.studio/thrive` |
| Screening, tras conversar | `healingthroughmovement.studio/thrive/form?de=Margaret` |
| Confirmación de la clase | `healingthroughmovement.studio/thrive/schedule?n=Ana` |

La raíz a secas (`healingthroughmovement.studio`) redirige a `/thrive/`. El día que
HTM tenga home propia, se reemplaza esa redirección — la genera `build.js`.

**Los slugs `form`, `schedule` y `assets` están reservados**: si una clienta se
llamara así, taparía una ruta del sitio. `build.js` los rechaza.

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
- **Validar las 6 preguntas** con Denisse. Están en `thrive/form/index.html`,
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
