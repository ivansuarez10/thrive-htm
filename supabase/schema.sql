-- ═══════════════════════════════════════════════════════════
--  THRIVE — esquema de la base
--
--  Pegar entero en el SQL Editor de Supabase y correr una vez.
--  Es idempotente: correrlo dos veces no rompe nada.
--
--  ⚠️ Esta tabla guarda INFORMACIÓN DE SALUD de personas reales:
--  condiciones cardiovasculares, diabetes, lesiones, síntomas de
--  esfuerzo. La regla que ordena todo lo de abajo es una sola:
--
--      cualquiera puede ESCRIBIR una solicitud.
--      nadie sin sesión puede LEER ninguna.
--
--  Por eso no hay política de SELECT para el rol anon. Si alguien
--  agrega una "para probar", queda expuesto el historial médico de
--  las clientas de Denisse.
-- ═══════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";

-- ── la tabla ──────────────────────────────────────────────
create table if not exists public.candidatas (
  id             uuid primary key default gen_random_uuid(),

  -- quién es
  nombre         text not null,
  telefono       text,

  -- de dónde salió
  origen         text not null default 'formulario'
                 check (origen in ('formulario','manual')),
  referida_por   text,

  -- ── la costura para los programas que vienen ──
  -- El panel es de HTM, no de THRIVE: mañana hay más programas y todos
  -- caen acá. Esta columna es lo único que hace falta hoy para que ese
  -- día no signifique migrar una tabla con personas reales adentro.
  -- No hay tabla 'programas' todavía A PROPÓSITO: el programa 2 no
  -- existe y su forma real no se conoce. Inventarla ahora sería
  -- inventarla mal. El slug obligatorio evita que 'Thrive' y 'thrive'
  -- partan los datos en dos sin que nadie se entere.
  programa       text not null default 'thrive'
                 check (programa ~ '^[a-z0-9-]+$'),

  -- las 15 respuestas, tal como las manda el formulario
  respuestas     jsonb not null default '{}'::jsonb,
  consentimiento boolean not null default false,

  -- dónde va en el flujo
  estado         text not null default 'formulario'
                 check (estado in (
                   'invitada',        -- Denisse le mandó el link
                   'escribio',        -- contestó por WhatsApp
                   'formulario',      -- llenó las 15 preguntas
                   'clase_agendada',  -- tiene fecha de clase de prueba
                   'vino',            -- ya vino a la clase
                   'adentro',         -- entró al programa
                   'no',              -- no siguió
                   'lista_espera'     -- quiere, pero no hay cupo
                 )),
  grupo          text check (grupo in ('2X','3X')),
  plazo          text check (plazo in ('mes','trimestre')),
  clase_en       timestamptz,

  -- lo que Denisse anota, que no sale de acá
  notas          text,

  -- ¿hay que hablar antes de ponerla a entrenar?
  -- Sale de las preguntas 11 y 12 del cuestionario: restricción médica
  -- indicada por un profesional, o síntomas durante el esfuerzo.
  alerta_salud   boolean generated always as (
                   respuestas->>'restriccion' = 'Sí.'
                   or respuestas->>'sintomas' = 'Sí.'
                 ) stored,

  creada_en      timestamptz not null default now(),
  actualizada_en timestamptz not null default now()
);

comment on table public.candidatas is
  'Mujeres invitadas a THRIVE y sus respuestas del cuestionario pre-trial. Contiene información de salud: nunca exponer al rol anon.';
comment on column public.candidatas.alerta_salud is
  'Se calcula sola. true = contestó que sí a la 11 o la 12. No agendar clase sin hablar antes.';

create index if not exists candidatas_estado_idx   on public.candidatas (estado);
create index if not exists candidatas_programa_idx on public.candidatas (programa);
create index if not exists candidatas_creada_idx on public.candidatas (creada_en desc);
create index if not exists candidatas_alerta_idx on public.candidatas (alerta_salud) where alerta_salud;

-- ── actualizada_en se mantiene sola ───────────────────────
create or replace function public.tocar_actualizada_en()
returns trigger language plpgsql as $$
begin
  new.actualizada_en = now();
  return new;
end $$;

drop trigger if exists candidatas_tocar on public.candidatas;
create trigger candidatas_tocar
  before update on public.candidatas
  for each row execute function public.tocar_actualizada_en();

-- ── seguridad ─────────────────────────────────────────────
alter table public.candidatas enable row level security;

-- Se borran primero para que correr esto dos veces no duplique nada.
drop policy if exists "cualquiera puede enviar el formulario"  on public.candidatas;
drop policy if exists "denisse lee todo"                        on public.candidatas;
drop policy if exists "denisse edita todo"                      on public.candidatas;
drop policy if exists "denisse agrega a mano"                   on public.candidatas;
-- (la de borrar ya no se crea; ver el candado más abajo)

-- El formulario es público: no hay login antes de contestar.
-- Solo INSERT, y solo con lo que el formulario manda.
create policy "cualquiera puede enviar el formulario"
  on public.candidatas for insert
  to anon
  with check (
    origen = 'formulario'
    and estado = 'formulario'
    and consentimiento = true          -- sin consentimiento no se guarda
    and length(nombre) between 2 and 120
    and notas is null                  -- las notas son de Denisse, no de quien llena
  );

-- ⚠️ NO existe "for select to anon". Es a propósito. No agregarla.

create policy "denisse lee todo"
  on public.candidatas for select to authenticated using (true);

create policy "denisse edita todo"
  on public.candidatas for update to authenticated using (true) with check (true);

create policy "denisse agrega a mano"
  on public.candidatas for insert to authenticated with check (true);

-- ⚠️ La política de borrado se RETIRÓ el 26 ago 2026. Nada en la
-- aplicación borra: el panel no tiene botón y el formulario solo
-- inserta. Si vuelve a hacer falta, se agrega a mano y con motivo.
drop policy if exists "denisse borra" on public.candidatas;

-- ── el candado ───────────────────────────────────────────
-- El 26 de agosto alguien limpiando datos de prueba corrió
-- «delete from candidatas» sin where y se llevó las cuatro filas,
-- incluido el registro real de Denisse. La RLS no lo impidió porque
-- el editor SQL del dashboard corre como DUEÑO, y al dueño la RLS
-- no le aplica. Un trigger sí le aplica.
--
-- Borrar sigue siendo posible, pero hay que declararlo en la misma
-- transacción. Esa fricción es exactamente el punto.
create or replace function public.no_borrar_candidatas()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.borrar_candidatas', true), '') = 'si' then
    return old;
  end if;
  raise exception 'Las candidatas no se borran.'
    using hint = 'Para dar de baja a alguien poné estado = ''no''. Si de verdad hay que borrar: begin; set local app.borrar_candidatas = ''si''; delete ...; commit;';
end $$;

drop trigger if exists candidatas_no_borrar on public.candidatas;
create trigger candidatas_no_borrar
  before delete on public.candidatas
  for each row execute function public.no_borrar_candidatas();

-- ⚠️ El de arriba NO cubre TRUNCATE. Un trigger BEFORE DELETE por fila
-- no se dispara con truncate: la tabla se vacía sin que salte nada.
-- Por eso hace falta este otro, a nivel de sentencia. Y este no lleva
-- escape: vaciar la tabla entera no es una operación que alguien
-- necesite. Si de verdad hiciera falta, se quita el trigger a propósito.
create or replace function public.no_vaciar_candidatas()
returns trigger language plpgsql as $$
begin
  raise exception 'La tabla candidatas no se vacía.'
    using hint = 'Un truncate acá borra el historial médico de personas reales. Si de verdad hace falta, hay que quitar el trigger candidatas_no_vaciar a propósito.';
end $$;

drop trigger if exists candidatas_no_vaciar on public.candidatas;
create trigger candidatas_no_vaciar
  before truncate on public.candidatas
  for each statement execute function public.no_vaciar_candidatas();

-- Lo que estos candados NO pueden cubrir, y hay que saberlo:
--   · drop table candidatas  — ningún trigger lo detiene. Haría falta un
--     event trigger, y eso pide superusuario: en Supabase el rol
--     'postgres' NO es superusuario (verificado el 26 ago 2026).
--   · quitar el trigger y después borrar — quien tenga acceso de dueño
--     puede hacerlo. Los candados frenan el accidente, no la intención.
-- Contra esos dos casos lo único que sirve es tener una copia.

-- ── cupos: 4 por grupo, 8 en total ────────────────────────
-- Vista para que el panel no tenga que contar en el navegador.
create or replace view public.cupos as
select
  g.grupo,
  4 as capacidad,
  count(c.id) filter (where c.estado = 'adentro') as ocupados,
  4 - count(c.id) filter (where c.estado = 'adentro') as libres
from (values ('2X'),('3X')) as g(grupo)
left join public.candidatas c on c.grupo = g.grupo
group by g.grupo;

-- La vista hereda el RLS de la tabla, así que anon tampoco la lee.
alter view public.cupos set (security_invoker = on);

-- ═══════════════════════════════════════════════════════════
--  Después de correr esto:
--
--  1. Authentication → Users → Add user → el correo de Denisse
--     con una contraseña. Marcar "Auto Confirm User" para no
--     depender del envío de correos.
--
--  2. Authentication → Providers → desactivar "Enable email
--     signups". Si queda encendido, cualquiera puede crearse una
--     cuenta y su sesión pasa a ser 'authenticated', o sea que
--     leería todas las respuestas. Es la puerta que más fácil se
--     deja abierta.
--
--  3. Settings → API → copiar Project URL y la clave anon a
--     sitio/config.js, y poner supabase.enabled en true.
--     La clave anon es pública por diseño: lo que protege los
--     datos son las políticas de arriba, no la clave.
-- ═══════════════════════════════════════════════════════════
