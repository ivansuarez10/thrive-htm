-- ══════════════════════════════════════════════════════════════════
-- CERRAR EL AVISO CON SU RESULTADO REAL — 3 sep 2026
--
-- El problema que esto resuelve, con nombre y fecha: entre que se
-- construyó el sistema de avisos y el 3 de septiembre, NINGÚN correo
-- se envió —faltaba la clave de Resend— y nadie se enteró durante
-- meses. Denisse supo que algo fallaba cuando una clienta le dijo
-- «yo sí llené el formulario».
--
-- ¿Por qué no se notó? Porque `avisar_inscripcion` marca el aviso
-- como 'enviado' ANTES de que Resend conteste. `net.http_post` es
-- asíncrono a propósito: devuelve un número y sigue, para no dejar a
-- una mujer esperando en el formulario mientras viaja un correo. La
-- respuesta llega unos segundos después a `net._http_response`.
--
-- Y ahí se quedaba. Nadie la iba a buscar.
--
-- Esto va a buscarla. El comentario de `aviso-correo.sql` decía «un
-- aviso que no salió tiene que poder verse»; esta es esa mitad.
-- ══════════════════════════════════════════════════════════════════

-- Dos estados nuevos. 'enviado' pasa a significar lo que siempre
-- significó de verdad: ENCOLADO, todavía no sabemos.
alter table public.avisos drop constraint if exists avisos_estado_check;
alter table public.avisos add constraint avisos_estado_check
  check (estado in ('enviado','entregado','rebotado','sin_configurar','error'));

comment on column public.avisos.estado is
  'enviado = encolado, sin respuesta todavía · entregado = Resend lo aceptó · rebotado = Resend lo rechazó, el motivo está en detalle · sin_configurar = ni se intentó · error = revento el disparador';

alter table public.avisos add column if not exists cerrado_en timestamptz;


-- ══════════ EL QUE VA A BUSCAR LA RESPUESTA ══════════
create or replace function public.cerrar_avisos()
returns integer
language plpgsql
security definer set search_path = public, net, pg_temp as $$
declare
  v_n integer := 0;
begin
  -- Los que ya tienen respuesta: se cierran con lo que dijo Resend.
  with cerrados as (
    update public.avisos a
       set estado = case when r.status_code between 200 and 299
                         then 'entregado' else 'rebotado' end,
           detalle = case when r.status_code between 200 and 299 then null
                          else left(coalesce(r.error_msg, r.content, 'sin cuerpo'), 400) end,
           cerrado_en = now()
      from net._http_response r
     where r.id = a.peticion_id
       and a.estado = 'enviado'
    returning 1)
  select count(*) into v_n from cerrados;

  -- ⚠️ Y los que nunca la van a tener. pg_net LIMPIA sus respuestas
  -- a las pocas horas: un aviso cuya respuesta ya se borró se
  -- quedaría en 'enviado' para siempre, que es exactamente la
  -- mentira que esto viene a matar. Pasada una hora sin respuesta,
  -- se cierra diciendo que no se sabe — que es la verdad.
  update public.avisos
     set estado = 'rebotado',
         detalle = 'pg_net no dejó respuesta (se limpió antes de leerla)',
         cerrado_en = now()
   where estado = 'enviado'
     and creado_en < now() - interval '1 hour'
     and not exists (select 1 from net._http_response r where r.id = peticion_id);

  return v_n;
end $$;

revoke all on function public.cerrar_avisos() from anon, authenticated;


-- ══════════ QUE CORRA SOLO ══════════
-- Cada minuto. Es una consulta diminuta sobre una tabla de decenas
-- de filas; el costo es despreciable al lado de no enterarse.
create extension if not exists pg_cron with schema extensions;

select cron.unschedule('cerrar-avisos') where exists
  (select 1 from cron.job where jobname = 'cerrar-avisos');

select cron.schedule('cerrar-avisos', '* * * * *', 'select public.cerrar_avisos()');


-- ══════════ LO QUE MIRA EL PANEL ══════════
-- Una sola fila con lo que hace falta saber. Si `fallidos` es mayor
-- que cero, el panel lo dice en voz alta: ese es el punto entero.
create or replace view public.avisos_salud as
select
  count(*) filter (where estado = 'entregado')                    as entregados,
  count(*) filter (where estado in ('rebotado','error'))          as fallidos,
  count(*) filter (where estado = 'sin_configurar')               as sin_configurar,
  count(*) filter (where estado = 'enviado')                      as en_vuelo,
  max(creado_en) filter (where estado in ('rebotado','error'))    as ultimo_fallo,
  (select left(detalle, 200) from public.avisos
    where estado in ('rebotado','error') order by creado_en desc limit 1) as motivo
from public.avisos;

alter view public.avisos_salud set (security_invoker = on);
grant select on public.avisos_salud to authenticated;
