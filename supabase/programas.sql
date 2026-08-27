-- ═══════════════════════════════════════════════════════════
--  HTM — de un programa a varios
--
--  El panel dejó de ser el panel de THRIVE. Denisse corre además
--  1:1, Teens Summer Camp y Taller de caídas, y va a correr más.
--
--  Lo que cambia de raíz: LA PERSONA DEJA DE SER LA FILA.
--  Antes una fila de `candidatas` era «una mujer en THRIVE». Una
--  mujer que hace 1:1 y después entra a THRIVE son dos filas con el
--  mismo teléfono, y las notas de una no las ve la otra. Ahora la
--  persona es durable y lo que se repite es la INSCRIPCIÓN.
--
--  ⚠️ Esto reemplaza la decisión escrita en schema.sql de NO crear
--  una tabla `programas` «porque el programa 2 no existe y su forma
--  real no se conoce». Ese razonamiento era correcto el 26 de agosto.
--  El 27 Ivan nombró los tres programas: ya existen.
--
--  ⚠️ `candidatas` NO se borra ni se rompe: se convierte en vista
--  sobre las tablas nuevas, con un disparador que traduce los INSERT.
--  El formulario público sigue escribiendo exactamente igual.
--
--  Correr en el SQL Editor de Supabase. Es idempotente.
-- ═══════════════════════════════════════════════════════════


-- ══════════ 1 · PROGRAMAS ══════════
-- El embudo es DATO, no código. Un taller de un día no tiene «clase
-- de prueba» ni «grupo 2X», y forzarle los estados de THRIVE sería
-- ponerle a Denisse casillas que no significan nada.
create table if not exists public.programas (
  id          text primary key check (id ~ '^[a-z0-9-]+$'),
  nombre      text not null,
  subtitulo   text,
  activo      boolean not null default true,
  orden       smallint not null default 100,

  -- [{"id":"invitada","nombre":"Invitada"}, …] en orden del flujo.
  -- `cierra: true` marca los estados de los que ya no se espera nada:
  -- el panel deja de pedir tareas sobre esa persona. Sin esto, quien
  -- ya entró o ya dijo que no seguiría apareciendo como pendiente.
  estados     jsonb not null,

  -- ⚠️ true = los estados son un punto de partida, no una decisión.
  -- El panel lo dice en voz alta para que nadie los tome por buenos.
  provisional boolean not null default false,

  -- Lo propio de cada uno: precios, días, cupos, fechas. Libre a
  -- propósito — un taller cobra por sesión y un trimestre por mes, y
  -- meterlos en las mismas columnas obliga a dejar la mitad en null.
  ajustes     jsonb not null default '{}'::jsonb,

  -- Rutas públicas. Solo THRIVE tiene, y por ahora se queda así.
  ruta_form   text,
  ruta_pase   text,

  creado_en   timestamptz not null default now()
);

insert into public.programas (id, nombre, subtitulo, orden, provisional, estados, ajustes, ruta_form, ruta_pase)
values
  ('thrive', 'THRIVE', 'Small Group Strength for Women', 10, false,
   '[{"id":"invitada","nombre":"Invitada"},
     {"id":"escribio","nombre":"Escribió"},
     {"id":"formulario","nombre":"Llenó el formulario"},
     {"id":"clase_agendada","nombre":"Clase agendada"},
     {"id":"vino","nombre":"Vino a la clase"},
     {"id":"adentro","nombre":"Adentro","cierra":true},
     {"id":"lista_espera","nombre":"Lista de espera"},
     {"id":"no","nombre":"No siguió","cierra":true}]'::jsonb,
   '{"cupos_por_grupo":4,"hora":"7:30 a.m.","grupos":[{"id":"2X","dias":"martes y jueves","precio":220},{"id":"3X","dias":"lunes, miércoles y viernes","precio":300}]}'::jsonb,
   '/thrive/form/', '/thrive/schedule/'),

  ('uno-a-uno', '1:1', 'Entrenamiento individual', 20, true,
   '[{"id":"interesada","nombre":"Interesada"},
     {"id":"conversando","nombre":"Conversando"},
     {"id":"sesion_agendada","nombre":"Sesión agendada"},
     {"id":"activa","nombre":"Activa","cierra":true},
     {"id":"pausada","nombre":"En pausa"},
     {"id":"no","nombre":"No siguió","cierra":true}]'::jsonb,
   '{}'::jsonb, null, null),

  ('teens-verano', 'Teens Summer Camp', 'Campamento de verano', 30, true,
   '[{"id":"interesada","nombre":"Preguntó"},
     {"id":"conversando","nombre":"Conversando"},
     {"id":"inscrita","nombre":"Inscrita"},
     {"id":"pago","nombre":"Pagó"},
     {"id":"vino","nombre":"Participó","cierra":true},
     {"id":"no","nombre":"No siguió","cierra":true}]'::jsonb,
   '{}'::jsonb, null, null),

  ('taller-caidas', 'Taller de caídas', 'Prevención de caídas', 40, true,
   '[{"id":"interesada","nombre":"Preguntó"},
     {"id":"inscrita","nombre":"Inscrita"},
     {"id":"pago","nombre":"Pagó"},
     {"id":"vino","nombre":"Asistió","cierra":true},
     {"id":"no","nombre":"No siguió","cierra":true}]'::jsonb,
   '{}'::jsonb, null, null)
on conflict (id) do nothing;


-- ══════════ 2 · PERSONAS ══════════
-- Quién es, una sola vez. Sin estado y sin programa: eso vive en la
-- inscripción. Las notas de acá son sobre LA PERSONA («vive cerca»,
-- «es hermana de Ana»); las de la inscripción son sobre ese programa.
create table if not exists public.personas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null check (char_length(btrim(nombre)) between 2 and 120),
  telefono   text,
  notas      text,

  -- Las que ya entrenan con Denisse y reparten invitaciones. Antes
  -- era una tabla aparte (`clientas`) y era la misma gente contada dos
  -- veces: una clienta puede además estar inscrita en otro programa.
  es_clienta boolean not null default false,
  activa     boolean not null default true,

  creada_en  timestamptz not null default now()
);

create index if not exists personas_clienta_idx on public.personas (es_clienta) where es_clienta;

comment on table public.personas is
  'Las personas, una vez cada una. Su participación en cada programa vive en `inscripciones`.';


-- ══════════ 3 · INSCRIPCIONES ══════════
create table if not exists public.inscripciones (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references public.personas(id) on delete restrict,
  programa_id    text not null references public.programas(id) on delete restrict,

  -- Validado contra programas.estados por un disparador, no por un
  -- CHECK: la lista vive en otra tabla y cambia por programa.
  estado         text not null,

  origen         text not null default 'manual'
                 check (origen in ('formulario','manual')),
  referida_por   text,

  respuestas     jsonb not null default '{}'::jsonb,
  consentimiento boolean not null default false,

  -- Sirven en todos los programas: en qué cohorte va y cuándo es su
  -- primera vez. En THRIVE son el grupo 2X/3X y la clase de prueba.
  grupo          text,
  clase_en       timestamptz,

  notas          text,
  datos          jsonb not null default '{}'::jsonb,

  -- Misma fórmula que tenía candidatas: preguntas 11 y 12.
  -- Un programa sin cuestionario deja respuestas en {} y sale false.
  alerta_salud   boolean generated always as (
                   respuestas->>'restriccion' = 'Sí.'
                   or respuestas->>'sintomas' = 'Sí.'
                 ) stored,

  creada_en      timestamptz not null default now(),
  actualizada_en timestamptz not null default now(),

  -- Una persona no se inscribe dos veces al mismo programa. Si vuelve
  -- en la siguiente edición, es la misma inscripción que cambia de
  -- estado — y su historial se queda.
  unique (persona_id, programa_id)
);

create index if not exists inscripciones_programa_idx on public.inscripciones (programa_id, estado);
create index if not exists inscripciones_creada_idx   on public.inscripciones (creada_en desc);
create index if not exists inscripciones_alerta_idx   on public.inscripciones (alerta_salud) where alerta_salud;

comment on table public.inscripciones is
  'Persona × programa. Contiene respuestas del cuestionario con información de salud: nunca exponer al rol anon.';

create or replace function public.tocar_inscripcion()
returns trigger language plpgsql as $$
begin new.actualizada_en = now(); return new; end $$;

drop trigger if exists inscripciones_tocar on public.inscripciones;
create trigger inscripciones_tocar before update on public.inscripciones
  for each row execute function public.tocar_inscripcion();

-- El estado tiene que existir en el embudo de SU programa. Sin esto,
-- 'clase_agendada' entraría en el Taller de caídas y el panel
-- mostraría una casilla que no significa nada ahí.
-- ⚠️ SECURITY DEFINER, y hace falta: el disparador consulta
-- `programas`, que tiene RLS y ninguna política para anon. Corriendo
-- como quien llama, la consulta volvía vacía para el formulario
-- público y TODO estado quedaba «inválido» — el formulario devolvía
-- 400 y la respuesta se perdía. El search_path fijo es obligatorio en
-- una función definer: sin él, quien pueda crear objetos en otro
-- esquema puede secuestrar los nombres de adentro.
create or replace function public.estado_valido()
returns trigger language plpgsql
security definer set search_path = public, pg_temp as $$
declare existe boolean;
begin
  select exists (
    select 1 from public.programas p, jsonb_array_elements(p.estados) e
    where p.id = new.programa_id and e->>'id' = new.estado
  ) into existe;
  if not existe then
    raise exception 'El estado "%" no existe en el programa "%".', new.estado, new.programa_id
      using hint = 'Los estados de cada programa viven en programas.estados. Agregalo ahí primero.';
  end if;
  return new;
end $$;

drop trigger if exists inscripciones_estado on public.inscripciones;
create trigger inscripciones_estado before insert or update of estado, programa_id
  on public.inscripciones for each row execute function public.estado_valido();


-- ══════════ 4 · LOS CANDADOS ══════════
-- Misma regla dura que candidatas, por la misma razón: el 26 de agosto
-- un `delete from candidatas` sin where se llevó cuatro filas. Ver
-- «El día que se borró la tabla» en CLAUDE.md.
create or replace function public.no_borrar()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.borrar', true), '') = 'si' then
    return old;
  end if;
  raise exception 'Acá no se borra. Para dar de baja: estado o activa=false.'
    using hint = 'Si de verdad hace falta: begin; set local app.borrar = ''si''; …; commit;';
end $$;

create or replace function public.no_vaciar()
returns trigger language plpgsql as $$
begin
  raise exception 'Un truncate acá borra historial de personas reales.'
    using hint = 'Sin escape a propósito: hay que quitar el disparador a mano.';
end $$;

drop trigger if exists personas_no_borrar on public.personas;
create trigger personas_no_borrar before delete on public.personas
  for each row execute function public.no_borrar();
drop trigger if exists personas_no_vaciar on public.personas;
create trigger personas_no_vaciar before truncate on public.personas
  for each statement execute function public.no_vaciar();

drop trigger if exists inscripciones_no_borrar on public.inscripciones;
create trigger inscripciones_no_borrar before delete on public.inscripciones
  for each row execute function public.no_borrar();
drop trigger if exists inscripciones_no_vaciar on public.inscripciones;
create trigger inscripciones_no_vaciar before truncate on public.inscripciones
  for each statement execute function public.no_vaciar();


-- ══════════ 5 · MIGRAR LO QUE HAY ══════════
-- Una persona por candidata. NO se intenta unir por nombre ni por
-- teléfono: adivinar identidades con tres filas y un homónimo sale
-- mucho más caro que dejar dos fichas para que Denisse las junte.
insert into public.personas (id, nombre, telefono, notas, creada_en)
select c.id, c.nombre, c.telefono, null, c.creada_en
from public.candidatas c
where not exists (select 1 from public.personas p where p.id = c.id);

insert into public.inscripciones (
  persona_id, programa_id, estado, origen, referida_por,
  respuestas, consentimiento, grupo, clase_en, notas, creada_en, actualizada_en)
select
  c.id, coalesce(c.programa,'thrive'), c.estado, c.origen, c.referida_por,
  c.respuestas, c.consentimiento, c.grupo, c.clase_en, c.notas, c.creada_en, c.actualizada_en
from public.candidatas c
where not exists (
  select 1 from public.inscripciones i
  where i.persona_id = c.id and i.programa_id = coalesce(c.programa,'thrive')
);

-- Las clientas pasan a ser personas marcadas. La tabla se queda vacía
-- pero no se borra: borrarla es exactamente lo que la regla prohíbe.
insert into public.personas (id, nombre, telefono, notas, es_clienta, activa, creada_en)
select cl.id, cl.nombre, cl.telefono, cl.notas, true, cl.activa, cl.creada_en
from public.clientas cl
where not exists (select 1 from public.personas p where p.id = cl.id);


-- ══════════ 6 · RLS ══════════
alter table public.programas     enable row level security;
alter table public.personas      enable row level security;
alter table public.inscripciones enable row level security;

drop policy if exists "denisse ve los programas"    on public.programas;
drop policy if exists "denisse edita los programas" on public.programas;
create policy "denisse ve los programas"
  on public.programas for select to authenticated using (true);
create policy "denisse edita los programas"
  on public.programas for update to authenticated using (true) with check (true);

drop policy if exists "denisse ve las personas"     on public.personas;
drop policy if exists "denisse agrega personas"     on public.personas;
drop policy if exists "denisse edita las personas"  on public.personas;
create policy "denisse ve las personas"
  on public.personas for select to authenticated using (true);
create policy "denisse agrega personas"
  on public.personas for insert to authenticated with check (true);
create policy "denisse edita las personas"
  on public.personas for update to authenticated using (true) with check (true);

drop policy if exists "denisse ve las inscripciones"    on public.inscripciones;
drop policy if exists "denisse agrega inscripciones"    on public.inscripciones;
drop policy if exists "denisse edita las inscripciones" on public.inscripciones;
create policy "denisse ve las inscripciones"
  on public.inscripciones for select to authenticated using (true);
create policy "denisse agrega inscripciones"
  on public.inscripciones for insert to authenticated with check (true);
create policy "denisse edita las inscripciones"
  on public.inscripciones for update to authenticated using (true) with check (true);

-- El público solo puede hacer una cosa: mandar el formulario. Mismas
-- condiciones exactas que tenía candidatas, más el programa: nadie
-- entra por el formulario a un programa que no tiene formulario.
drop policy if exists "el formulario crea la persona"      on public.personas;
create policy "el formulario crea la persona"
  on public.personas for insert to anon
  with check (
    es_clienta = false
    and notas is null
    and char_length(btrim(nombre)) between 2 and 120
  );

drop policy if exists "el formulario crea la inscripción"  on public.inscripciones;
create policy "el formulario crea la inscripción"
  on public.inscripciones for insert to anon
  with check (
    origen = 'formulario'
    and estado = 'formulario'
    and programa_id = 'thrive'
    and notas is null
    and clase_en is null
    and jsonb_typeof(respuestas) = 'object'
  );

-- Sin política de SELECT para anon en ninguna de las dos, a propósito:
-- cualquiera escribe su solicitud, nadie sin sesión lee ninguna.


-- ══════════ 7 · `candidatas` SIGUE EXISTIENDO ══════════
-- El formulario público escribe en `candidatas` y lo mantiene otra
-- sesión. Romperlo significa que una mujer llena quince preguntas,
-- ve «gracias», y el dato se pierde en silencio.
-- Así que la tabla se guarda con su nombre viejo y `candidatas` pasa
-- a ser una vista que traduce en las dos direcciones.
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='candidatas'
               and table_type='BASE TABLE') then
    execute 'alter table public.candidatas rename to candidatas_v1';
  end if;
end $$;

create or replace view public.candidatas as
select
  i.persona_id                as id,
  p.nombre,
  p.telefono,
  i.origen,
  i.programa_id               as programa,
  i.referida_por,
  i.respuestas,
  i.consentimiento,
  i.estado,
  i.grupo,
  null::text                  as plazo,
  i.clase_en,
  i.notas,
  i.alerta_salud,
  i.creada_en,
  i.actualizada_en
from public.inscripciones i
join public.personas p on p.id = i.persona_id;

alter view public.candidatas set (security_invoker = on);
grant select, insert on public.candidatas to anon, authenticated;

-- Un INSERT en la vista se parte en dos: la persona y su inscripción.
-- No se busca una persona existente a propósito — ver el comentario
-- de la migración.
-- ⚠️ Sin RETURNING, y no es estilo: `insert … returning` hace que
-- PostgreSQL evalúe además la política de SELECT sobre la fila nueva,
-- y anon no tiene política de lectura sobre `personas` — ni debe
-- tenerla. Con RETURNING el formulario devolvía 401 y la respuesta se
-- perdía. El id se genera antes y se inserta explícito.
create or replace function public.candidatas_insert()
returns trigger language plpgsql as $$
declare nueva uuid := gen_random_uuid();
begin
  insert into public.personas (id, nombre, telefono)
  values (nueva, new.nombre, new.telefono);

  insert into public.inscripciones (
    persona_id, programa_id, estado, origen, referida_por,
    respuestas, consentimiento, grupo, clase_en)
  values (
    nueva,
    coalesce(new.programa, 'thrive'),
    coalesce(new.estado, 'formulario'),
    coalesce(new.origen, 'formulario'),
    new.referida_por,
    coalesce(new.respuestas, '{}'::jsonb),
    coalesce(new.consentimiento, false),
    new.grupo,
    new.clase_en);

  new.id := nueva;
  return new;
end $$;

drop trigger if exists candidatas_insert_tr on public.candidatas;
create trigger candidatas_insert_tr instead of insert on public.candidatas
  for each row execute function public.candidatas_insert();

-- Y el UPDATE, que es el que rompía el panel: guardar una ficha hacía
-- `update candidatas set …` y una vista sin disparador no sabe recibirlo.
-- Reparte los campos a donde viven ahora: nombre y teléfono son de la
-- persona, el resto es de la inscripción.
create or replace function public.candidatas_update()
returns trigger language plpgsql as $$
begin
  update public.personas
     set nombre = coalesce(new.nombre, nombre),
         telefono = new.telefono
   where id = old.id;

  update public.inscripciones
     set estado   = coalesce(new.estado, estado),
         grupo    = new.grupo,
         clase_en = new.clase_en,
         notas    = new.notas,
         referida_por = new.referida_por
   where persona_id = old.id
     and programa_id = coalesce(new.programa, old.programa, 'thrive');

  return new;
end $$;

drop trigger if exists candidatas_update_tr on public.candidatas;
create trigger candidatas_update_tr instead of update on public.candidatas
  for each row execute function public.candidatas_update();

grant update on public.candidatas to authenticated;


-- ══════════ 8 · CUPOS, sobre lo nuevo ══════════
-- La vista vieja seguía a la tabla renombrada y contaba filas viejas.
drop view if exists public.cupos;
create or replace view public.cupos as
select
  i.programa_id,
  i.grupo,
  count(*) filter (where i.estado = 'adentro')  as ocupados
from public.inscripciones i
where i.grupo is not null
group by i.programa_id, i.grupo;

alter view public.cupos set (security_invoker = on);
grant select on public.cupos to authenticated;


-- ══════════ 9 · COMPROBACIÓN ══════════
--   select count(*) from public.programas;      -- 4
--   select count(*) from public.personas;       -- las de antes
--   select count(*) from public.inscripciones;  -- una por candidata
--   select count(*) from public.candidatas;     -- lo mismo, por la vista
