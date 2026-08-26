-- ═══════════════════════════════════════════════════════════
--  THRIVE — lo que el panel de Denisse necesita además de
--  'candidatas'. Va aparte de schema.sql a propósito: aquel
--  describe el formulario, que es lo que toca el público.
--  Esto describe la herramienta, que solo toca ella.
--
--  Correr en el SQL Editor de Supabase. Es idempotente.
-- ═══════════════════════════════════════════════════════════


-- ══════════ 1 · AJUSTES ══════════
-- Una sola fila. Antes esto vivía en sitio/config.js, que es un
-- archivo estático: para cambiar un precio había que editar el
-- repo y publicar. Denisse no hace eso, así que en la práctica
-- los datos del programa los cambiaba Ivan o no los cambiaba
-- nadie. Acá los edita ella desde el panel.
--
-- El candado `check (id = 1)` es lo que hace que sea una sola
-- fila y no una tabla de filas sueltas: no hay "el ajuste
-- correcto" que adivinar, hay uno.
create table if not exists public.ajustes (
  id               smallint primary key default 1 check (id = 1),

  -- cómo la contactan
  whatsapp         text,

  -- el programa
  precio_2x        integer,
  precio_3x        integer,
  hora             text,
  dias_2x          text,
  dias_3x          text,
  periodo_inicio   date,
  periodo_fin      date,
  cupos_por_grupo  smallint not null default 4
                   check (cupos_por_grupo between 1 and 12),

  -- el estudio
  direccion        text,
  mapa             text,

  -- solo del panel, no del sitio
  -- Marca hasta dónde ya vio Denisse. Vive en la base y no en el
  -- navegador porque ella abre el panel desde el teléfono y desde
  -- la computadora, y "nuevas desde la última vez" tiene que
  -- significar lo mismo en los dos.
  panel_visto_en   timestamptz,

  actualizado_en   timestamptz not null default now()
);

insert into public.ajustes (id) values (1) on conflict (id) do nothing;

create or replace function public.tocar_ajustes()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

drop trigger if exists ajustes_tocados on public.ajustes;
create trigger ajustes_tocados before update on public.ajustes
  for each row execute function public.tocar_ajustes();

alter table public.ajustes enable row level security;

drop policy if exists "denisse lee los ajustes"  on public.ajustes;
drop policy if exists "denisse edita los ajustes" on public.ajustes;

create policy "denisse lee los ajustes"
  on public.ajustes for select to authenticated using (true);

create policy "denisse edita los ajustes"
  on public.ajustes for update to authenticated using (true) with check (true);

-- El sitio necesita leer precios, horarios y dirección sin que
-- nadie inicie sesión. Lo que NO necesita es `panel_visto_en`,
-- así que anon no ve la tabla: ve esta vista, que es la misma
-- información que ya está impresa en la landing.
create or replace view public.ajustes_publicos as
select
  whatsapp, precio_2x, precio_3x, hora, dias_2x, dias_3x,
  periodo_inicio, periodo_fin, cupos_por_grupo, direccion, mapa,
  actualizado_en
from public.ajustes
where id = 1;

alter view public.ajustes_publicos set (security_invoker = on);
grant select on public.ajustes_publicos to anon, authenticated;

-- security_invoker manda la consulta de vuelta contra la tabla con
-- los permisos de quien pregunta, y anon no tiene política de
-- select sobre `ajustes`. Sin esta política la vista sale vacía
-- para el público, que es justo el modo de fallar más confuso:
-- el sitio no da error, solo muestra precios en blanco.
drop policy if exists "el sitio lee los ajustes públicos" on public.ajustes;
create policy "el sitio lee los ajustes públicos"
  on public.ajustes for select to anon using (id = 1);

-- ⚠️ Pero la política de arriba, sola, le abre la tabla ENTERA al
-- público: probado con la clave anon, `select * from ajustes`
-- devolvía también `panel_visto_en`. La RLS filtra filas, no
-- columnas — eso se hace con permisos de columna.
--
-- Hoy lo que se filtraba era inofensivo (cuándo abrió Denisse el
-- panel). El problema real es el mañana: cualquier columna privada
-- que se agregue después nace pública si esto no está.
revoke all on public.ajustes from anon;
grant select (
  id, whatsapp, precio_2x, precio_3x, hora, dias_2x, dias_3x,
  periodo_inicio, periodo_fin, cupos_por_grupo, direccion, mapa,
  actualizado_en
) on public.ajustes to anon;


-- ══════════ 2 · CLIENTAS ══════════
-- Las mujeres que YA entrenan con Denisse. No son candidatas y no
-- van en esa tabla: no tienen estado, ni clase de prueba, ni
-- cuestionario de salud. Están acá por una sola razón — son las
-- que reparten las invitaciones.
--
-- El link de cada una lleva su nombre en ?de=, y ese nombre es lo
-- que después aparece en «la invitó Ana» en la ficha de quien
-- llegó. Por eso el nombre es el dato importante y no el teléfono.
create table if not exists public.clientas (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(btrim(nombre)) between 2 and 120),
  telefono    text,
  activa      boolean not null default true,
  notas       text,
  creada_en   timestamptz not null default now()
);

create index if not exists clientas_activa_idx on public.clientas (activa);

alter table public.clientas enable row level security;

-- Sin política para anon, y es deliberado: la lista de clientas de
-- Denisse es privada. El público solo llega por el link, y el link
-- no necesita que la tabla sea legible.
drop policy if exists "denisse ve sus clientas"      on public.clientas;
drop policy if exists "denisse agrega clientas"      on public.clientas;
drop policy if exists "denisse edita sus clientas"   on public.clientas;

create policy "denisse ve sus clientas"
  on public.clientas for select to authenticated using (true);

create policy "denisse agrega clientas"
  on public.clientas for insert to authenticated with check (true);

create policy "denisse edita sus clientas"
  on public.clientas for update to authenticated using (true) with check (true);

-- Igual que en candidatas: no se borra. Una clienta que se va se
-- marca `activa = false` y su historial queda.
-- Ver el candado de schema.sql, que explica por qué.


-- ══════════ 3 · COMPROBACIÓN ══════════
-- Correr esto después y leer las tres líneas:
--   select count(*) from public.ajustes;             -- 1
--   select count(*) from public.ajustes_publicos;    -- 1
--   select count(*) from public.clientas;            -- 0 al principio
