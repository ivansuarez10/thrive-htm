-- ═══════════════════════════════════════════════════════════
--  HTM — el panel se acuerda de lo que Denisse hizo
--
--  El agujero: ella tocaba «Escribirle», se iba a WhatsApp,
--  conversaba diez minutos y volvía — y el panel no sabía que eso
--  había pasado. La tarea seguía ahí, arriba, hasta que ella se
--  acordara de mover el estado a mano. Para una herramienta cuyo
--  trabajo entero es acordarse, olvidaba justo lo que importa.
--
--  Ahora cada cosa que pasa queda escrita. Dos fuentes:
--    · la base, sola, cuando cambia un estado (disparador)
--    · el panel, cuando ella confirma que escribió
--
--  Correr en el SQL Editor de Supabase. Es idempotente.
-- ═══════════════════════════════════════════════════════════


-- ══════════ 1 · EVENTOS ══════════
-- `persona_id` es obligatorio y `inscripcion_id` no: el hilo se lee
-- por persona. Si la misma señora hace 1:1 y después entra a THRIVE,
-- su historia es UNA sola aunque sean dos inscripciones — y eso era
-- medio motivo para separar persona de inscripción.
create table if not exists public.eventos (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references public.personas(id) on delete restrict,
  inscripcion_id uuid references public.inscripciones(id) on delete restrict,

  tipo           text not null check (tipo in ('alta','mensaje','estado','nota','sistema')),

  -- Lo que se lee en el hilo, ya escrito en español. Se guarda hecho
  -- y no armado al vuelo a propósito: si mañana cambia el nombre de un
  -- estado, lo que pasó en agosto siguió pasando como decía en agosto.
  detalle        text not null,

  -- El detalle en crudo, para lo que quiera leerlo una máquina.
  meta           jsonb not null default '{}'::jsonb,

  creado_en      timestamptz not null default now()
);

create index if not exists eventos_persona_idx     on public.eventos (persona_id, creado_en desc);
create index if not exists eventos_inscripcion_idx on public.eventos (inscripcion_id, creado_en desc);
-- El panel pregunta muy seguido «¿cuándo fue el último mensaje?», y esa
-- consulta filtra por tipo antes que por nada.
create index if not exists eventos_mensaje_idx     on public.eventos (inscripcion_id, creado_en desc) where tipo = 'mensaje';

comment on table public.eventos is
  'El hilo de cada persona. Puede citar textos de mensajes: nunca exponer al rol anon.';


-- ══════════ 2 · LA BASE SE ANOTA SOLA ══════════
-- El registro no puede depender de que la interfaz se acuerde de
-- escribirlo. Un cambio de estado desde el panel, desde el editor SQL
-- o desde donde sea queda anotado igual.
--
-- SECURITY DEFINER porque lee `programas` para traducir el estado a su
-- nombre, y `programas` tiene RLS. Es la misma trampa que ya mordió
-- con el disparador que valida estados: corriendo como quien llama, la
-- consulta vuelve vacía y el nombre sale en crudo.
create or replace function public.registrar_estado()
returns trigger language plpgsql
security definer set search_path = public, pg_temp as $$
declare nom text;
begin
  if new.estado is distinct from old.estado then
    select e->>'nombre' into nom
    from public.programas p, jsonb_array_elements(p.estados) e
    where p.id = new.programa_id and e->>'id' = new.estado;

    insert into public.eventos (persona_id, inscripcion_id, tipo, detalle, meta)
    values (new.persona_id, new.id, 'estado',
            'Pasó a «' || coalesce(nom, new.estado) || '»',
            jsonb_build_object('de', old.estado, 'a', new.estado));
  end if;
  return new;
end $$;

drop trigger if exists inscripciones_registrar on public.inscripciones;
create trigger inscripciones_registrar after update of estado on public.inscripciones
  for each row execute function public.registrar_estado();

create or replace function public.registrar_alta()
returns trigger language plpgsql
security definer set search_path = public, pg_temp as $$
declare nom text;
begin
  select nombre into nom from public.programas where id = new.programa_id;
  insert into public.eventos (persona_id, inscripcion_id, tipo, detalle, meta)
  values (new.persona_id, new.id, 'alta',
          'Entró a ' || coalesce(nom, new.programa_id) ||
          case when new.origen = 'formulario' then ' por el formulario' else ', agregada a mano' end,
          jsonb_build_object('origen', new.origen, 'programa', new.programa_id));
  return new;
end $$;

drop trigger if exists inscripciones_registrar_alta on public.inscripciones;
create trigger inscripciones_registrar_alta after insert on public.inscripciones
  for each row execute function public.registrar_alta();


-- ══════════ 3 · EL CANDADO ══════════
-- El hilo es el historial, y el historial es el producto.
drop trigger if exists eventos_no_borrar on public.eventos;
create trigger eventos_no_borrar before delete on public.eventos
  for each row execute function public.no_borrar();
drop trigger if exists eventos_no_vaciar on public.eventos;
create trigger eventos_no_vaciar before truncate on public.eventos
  for each statement execute function public.no_vaciar();


-- ══════════ 4 · RLS ══════════
alter table public.eventos enable row level security;

drop policy if exists "denisse ve el hilo"    on public.eventos;
drop policy if exists "denisse anota el hilo" on public.eventos;

create policy "denisse ve el hilo"
  on public.eventos for select to authenticated using (true);
create policy "denisse anota el hilo"
  on public.eventos for insert to authenticated with check (true);

-- Sin UPDATE y sin política para anon, las dos cosas a propósito: lo
-- que pasó no se edita, y el público no tiene nada que hacer acá.


-- ══════════ 5 · EL ÚLTIMO CONTACTO ══════════
-- El panel lo pregunta en cada pintada, una vez por inscripción. Como
-- vista sale en una consulta en vez de en cuarenta.
create or replace view public.ultimo_contacto as
select
  inscripcion_id,
  max(creado_en) filter (where tipo = 'mensaje') as ultimo_mensaje,
  max(creado_en)                                 as ultimo_movimiento
from public.eventos
where inscripcion_id is not null
group by inscripcion_id;

alter view public.ultimo_contacto set (security_invoker = on);
grant select on public.ultimo_contacto to authenticated;


-- ══════════ 6 · LO QUE YA PASÓ ══════════
-- Las inscripciones que existen desde antes de esta tabla no tienen
-- alta anotada. Se les pone una, con su fecha real, para que el hilo
-- no arranque en blanco.
insert into public.eventos (persona_id, inscripcion_id, tipo, detalle, meta, creado_en)
select i.persona_id, i.id, 'alta',
       'Entró a ' || coalesce(p.nombre, i.programa_id) ||
       case when i.origen = 'formulario' then ' por el formulario' else ', agregada a mano' end,
       jsonb_build_object('origen', i.origen, 'programa', i.programa_id, 'retroactivo', true),
       i.creada_en
from public.inscripciones i
left join public.programas p on p.id = i.programa_id
where not exists (
  select 1 from public.eventos e where e.inscripcion_id = i.id and e.tipo = 'alta'
);


-- ══════════ 7 · COMPROBACIÓN ══════════
--   select count(*) from public.eventos;          -- una por inscripción
--   select * from public.ultimo_contacto;
