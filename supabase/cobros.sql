-- ═══════════════════════════════════════════════════════════
--  HTM — los cobros
--
--  Lo que esto responde es UNA pregunta: «¿quién me debe?».
--  No es contabilidad y no quiere serlo. Denisse no necesita
--  libros: necesita saber, el 5 de octubre, quién no pagó
--  octubre. Una herramienta que hay que alimentar todos los días
--  se abandona en tres semanas.
--
--  ── La decisión de diseño que explica todo lo de abajo ──
--
--  LAS CUOTAS NO SE GUARDAN. SE CALCULAN.
--
--  Lo que se guarda son los PAGOS, que son hechos: alguien puso
--  plata un día. Lo que le TOCA pagar sale del programa —cuánto
--  vale su grupo, desde cuándo, hasta cuándo— y por eso cambiar
--  el período no obliga a migrar filas de nadie.
--
--  El corolario incómodo: la regla vive en el panel, en
--  JavaScript, no acá. Es a propósito. Escrita en los dos lados
--  se separan, y en este proyecto eso ya pasó —`config.js` y la
--  base diciendo precios distintos— así que la regla vive en un
--  solo lugar y este archivo solo guarda hechos.
--
--  Correr entero en el SQL Editor de Supabase. Es idempotente.
-- ═══════════════════════════════════════════════════════════


-- ══════════ 1 · DESDE CUÁNDO SE LE COBRA ══════════
-- Vacío significa «desde que arranca el programa», que es el caso
-- de las ocho del primer período. Se llena cuando alguien entra
-- tarde: quien empieza en octubre no debe septiembre, y sin esta
-- columna el panel le inventaría una deuda que no existe.
alter table public.inscripciones add column if not exists cobro_desde date;
alter table public.inscripciones add column if not exists cobro_hasta date;

comment on column public.inscripciones.cobro_desde is
  'Primer mes que se le cobra. Vacío = desde el inicio del período del programa.';
comment on column public.inscripciones.cobro_hasta is
  'Último mes que se le cobra. Se llena cuando alguien se va antes de que termine el período.';

-- ⚠️ `cobro_hasta` es lo que hace que irse no borre la deuda. Sin
-- ella habría que elegir entre dos cosas malas: seguirle generando
-- cuotas de meses en los que ya no entrena, o dejar de generarle
-- cuotas y perder de vista los meses que sí dejó debiendo. Con la
-- columna, quien se fue en octubre debiendo octubre sigue debiendo
-- octubre y no debe noviembre.


-- ══════════ 2 · LOS PAGOS ══════════
create table if not exists public.pagos (
  id             uuid primary key default gen_random_uuid(),

  -- Los dos, y no uno: `inscripcion_id` dice a qué programa
  -- corresponde y `persona_id` deja preguntar «cuánto me ha pagado
  -- ella en total» sin importar por cuántos programas pasó.
  inscripcion_id uuid not null references public.inscripciones(id) on delete restrict,
  persona_id     uuid not null references public.personas(id)      on delete restrict,

  -- Qué cubre. 'YYYY-MM' para lo mensual, 'unico' para un programa
  -- que se paga una sola vez. Texto y no date porque un mes NO es
  -- un día: guardar '2026-10-01' invita a que alguien lo compare
  -- con una fecha real y descubra que octubre «empieza» el día que
  -- ella pagó.
  periodo        text not null check (periodo = 'unico' or periodo ~ '^\d{4}-(0[1-9]|1[0-2])$'),

  monto          numeric(10,2) not null check (monto > 0),
  pagado_en      date not null,
  medio          text check (medio in ('transferencia','efectivo','otro')),
  nota           text,

  -- ⚠️ Un pago mal registrado NO se borra: se anula, y queda la
  -- fila diciendo que se anuló. Es la misma regla dura de las
  -- candidatas, y acá pesa más — una discusión de plata en enero
  -- necesita evidencia de qué se registró y qué se deshizo.
  anulado        boolean not null default false,
  anulado_motivo text,

  creado_en      timestamptz not null default now()
);

-- El panel pregunta «¿qué pagó ésta?» una vez por inscripción en
-- cada pintada.
create index if not exists pagos_inscripcion_idx on public.pagos (inscripcion_id, periodo);
create index if not exists pagos_persona_idx     on public.pagos (persona_id, pagado_en desc);
-- El resumen del mes filtra por fecha de pago antes que por nada.
create index if not exists pagos_fecha_idx       on public.pagos (pagado_en desc) where not anulado;

-- ⚠️ NO hay índice único por (inscripcion_id, periodo), y no es un
-- olvido: alguien puede pagar octubre en dos partes. Lo que decide
-- si octubre está saldado es la SUMA de sus pagos contra lo que
-- vale su grupo, no la existencia de una fila. Un único acá
-- volvería imposible el pago partido, que es de lo más común.

comment on table public.pagos is
  'Pagos recibidos. Las cuotas esperadas NO viven acá: se calculan en el panel desde el programa.';


-- ══════════ 3 · LOS CANDADOS ══════════
-- Mismas funciones genéricas que el resto del modelo. Un pago
-- borrado es plata que alguien entregó y de la que no queda rastro.
drop trigger if exists pagos_no_borrar on public.pagos;
create trigger pagos_no_borrar before delete on public.pagos
  for each row execute function public.no_borrar();
drop trigger if exists pagos_no_vaciar on public.pagos;
create trigger pagos_no_vaciar before truncate on public.pagos
  for each statement execute function public.no_vaciar();


-- ══════════ 4 · RLS ══════════
alter table public.pagos enable row level security;

drop policy if exists "denisse ve los pagos"      on public.pagos;
drop policy if exists "denisse registra pagos"    on public.pagos;
drop policy if exists "denisse corrige un pago"   on public.pagos;

create policy "denisse ve los pagos"
  on public.pagos for select to authenticated using (true);
create policy "denisse registra pagos"
  on public.pagos for insert to authenticated with check (true);
-- UPDATE existe solo para poder ANULAR. Sin él, un pago tecleado
-- mal quedaría para siempre y no habría forma de corregirlo sin
-- borrar, que es justo lo que no se puede hacer.
create policy "denisse corrige un pago"
  on public.pagos for update to authenticated using (true) with check (true);

-- Sin política para anon, y sin `grant` de columnas: el público no
-- tiene absolutamente nada que hacer acá. La tabla dice cuánto
-- paga cada mujer por su entrenamiento.
revoke all on public.pagos from anon;


-- ══════════ 5 · EL PAGO ENTRA AL HILO ══════════
-- El hilo de cada persona es el registro de lo que pasó, y que
-- pagara es de lo más importante que pasa. `eventos.tipo` no
-- contemplaba 'pago' porque cuando se escribió no existían.
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check
  check (tipo in ('alta','mensaje','estado','nota','sistema','pago'));

create or replace function public.registrar_pago()
returns trigger language plpgsql
security definer set search_path = public, pg_temp as $$
declare
  v_cual text;
begin
  -- 'unico' no es un mes y decir «pagó unico» es ilegible.
  v_cual := case when new.periodo = 'unico' then '' else ' de ' || new.periodo end;

  if tg_op = 'INSERT' then
    insert into public.eventos (persona_id, inscripcion_id, tipo, detalle, meta)
    values (new.persona_id, new.inscripcion_id, 'pago',
            'Pagó ' || trim(to_char(new.monto, 'FM999999990.00')) || v_cual ||
            coalesce(' · ' || new.medio, ''),
            jsonb_build_object('periodo', new.periodo, 'monto', new.monto, 'medio', new.medio));
    return new;
  end if;

  -- La anulación también se anota. Un hilo que solo muestra los
  -- pagos que quedaron en pie miente sobre lo que se conversó.
  if tg_op = 'UPDATE' and new.anulado and not old.anulado then
    insert into public.eventos (persona_id, inscripcion_id, tipo, detalle, meta)
    values (new.persona_id, new.inscripcion_id, 'pago',
            'Se anuló el pago de ' || trim(to_char(new.monto, 'FM999999990.00')) || v_cual ||
            coalesce(': ' || nullif(btrim(new.anulado_motivo), ''), ''),
            jsonb_build_object('periodo', new.periodo, 'monto', new.monto, 'anulado', true));
  end if;
  return new;
end $$;

drop trigger if exists pagos_al_hilo on public.pagos;
create trigger pagos_al_hilo after insert or update on public.pagos
  for each row execute function public.registrar_pago();


-- ══════════ 6 · CÓMO COBRA CADA PROGRAMA ══════════
-- Va en `programas.ajustes`, igual que los estados, los grupos y
-- los cupos. La forma del cobro es distinta en cada programa y
-- cablearla en el panel es exactamente el error que ya se corrigió
-- con los embudos.
--
--   forma        'mensual' | 'unico'
--   vence_dia    día del mes en que vence la cuota
--   gracia_dias  cuántos días de atraso antes de que sea una tarea
--   moneda       el símbolo, tal como se escribe en la landing
--
-- El MONTO no va acá: ya vive en `ajustes.grupos[].precio`, uno por
-- grupo. Repetirlo sería tener dos precios que se pueden contradecir.
--
-- ⚠️ SOLO THRIVE. Los otros tres programas no llevan `cobro` y el
-- panel no les muestra nada de cobros — a propósito: cómo se cobran
-- 1:1, Teens y el Taller de caídas es una pregunta abierta para
-- Denisse desde el 27 de agosto, y con plata inventarlo cuesta más
-- caro que con un embudo.
update public.programas
   set ajustes = ajustes || jsonb_build_object(
         'cobro', jsonb_build_object(
           'forma', 'mensual',
           'vence_dia', 1,
           'gracia_dias', 5,
           'moneda', '$'))
 where id = 'thrive'
   and ajustes->'cobro' is null;


-- ══════════ 7 · COMPROBACIÓN ══════════
--   select ajustes->'cobro' from public.programas where id = 'thrive';
--   select * from public.pagos;
--
-- Que los candados están puestos (las dos tienen que FALLAR):
--   delete from public.pagos;
--   truncate table public.pagos;
--
-- Que anon no ve nada (con la clave pública, tiene que dar 42501):
--   select * from public.pagos;
