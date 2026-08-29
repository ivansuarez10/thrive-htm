-- ═══════════════════════════════════════════════════════════
--  HTM — el correo que avisa que llegó alguien
--
--  Hasta hoy el sistema NO notificaba nada. Lo que Denisse
--  recibía por WhatsApp era la clienta tocando un botón al final
--  del formulario: opcional, manual, y en primera persona de ella.
--  Si no lo tocaba, Denisse no se enteraba hasta abrir el panel.
--
--  Éste es el primer aviso automático, y sale DESDE LA BASE a
--  propósito: así no depende de que el navegador de la clienta
--  siga vivo. El insert entró, el correo sale. Punto.
--
--  ⚠️ El disparador NUNCA puede tumbar el insert. Si el correo
--  falla, la inscripción se guarda igual: perder el aviso es
--  molesto, perder a la candidata es el bug que ya tuvimos.
-- ═══════════════════════════════════════════════════════════

create extension if not exists pg_net with schema extensions;


-- ══════════ 1 · A DÓNDE SE MANDA ══════════
-- En `ajustes` para que Denisse lo cambie desde el panel sin tocar
-- código ni base. Si está vacío, no se manda nada y no falla nada.
alter table public.ajustes add column if not exists correo_aviso text;

comment on column public.ajustes.correo_aviso is
  'A dónde llega el aviso de inscripción nueva. Vacío = no se manda.';


-- ══════════ 2 · LA LLAVE ══════════
-- La clave de Resend va en el vault, NO en esta tabla ni en el repo,
-- que es público. Se guarda una sola vez, a mano:
--
--   select vault.create_secret('re_XXXXXXXX', 'resend_key');
--
-- Para rotarla:
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'resend_key'), 're_NUEVA');
create or replace function public.clave_resend()
returns text language sql stable
security definer set search_path = vault, public, pg_temp as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'resend_key' limit 1;
$$;
revoke all on function public.clave_resend() from anon, authenticated;


-- ══════════ 3 · EL REGISTRO ══════════
-- Un aviso que no salió tiene que poder verse. Es exactamente el
-- error que acabamos de arreglar en el formulario: fallar en
-- silencio y que nadie se entere hasta que falta alguien.
create table if not exists public.avisos (
  id             bigserial primary key,
  inscripcion_id uuid references public.inscripciones(id) on delete restrict,
  canal          text not null default 'correo',
  destino        text,
  estado         text not null default 'enviado'
                 check (estado in ('enviado','sin_configurar','error')),
  detalle        text,
  peticion_id    bigint,          -- el id de pg_net, para leer su respuesta
  creado_en      timestamptz not null default now()
);

alter table public.avisos enable row level security;
drop policy if exists "denisse ve los avisos" on public.avisos;
create policy "denisse ve los avisos"
  on public.avisos for select to authenticated using (true);
-- Sin insert para nadie: los escribe el disparador, que corre como dueño.


-- ══════════ 4 · EL AVISO ══════════
create or replace function public.avisar_inscripcion()
returns trigger language plpgsql
security definer set search_path = public, extensions, pg_temp as $$
declare
  v_clave   text;
  v_destino text;
  v_persona record;
  v_prog    record;
  v_grupo   text;
  v_alerta  text := '';
  v_asunto  text;
  v_html    text;
  v_pid     bigint;
  v_base    text := 'https://healingthroughmovement.studio';
begin
  select correo_aviso into v_destino from public.ajustes where id = 1;
  v_clave := public.clave_resend();

  if v_destino is null or btrim(v_destino) = '' or v_clave is null then
    insert into public.avisos (inscripcion_id, destino, estado, detalle)
    values (new.id, v_destino, 'sin_configurar',
            case when v_clave is null then 'falta la clave de Resend'
                 else 'falta correo_aviso en ajustes' end);
    return new;
  end if;

  select nombre, telefono into v_persona from public.personas where id = new.persona_id;
  select nombre into v_prog from public.programas where id = new.programa_id;

  v_grupo := coalesce(new.grupo, new.respuestas->>'grupo', 'sin definir');

  -- Se dice CUÁL respuesta levantó la alerta, igual que en el panel:
  -- «restricción o síntomas» le atribuye a alguien algo que negó.
  if new.respuestas->>'restriccion' = 'Sí.' then
    v_alerta := v_alerta || '<li>Restricción médica para hacer ejercicio' ||
      coalesce(': «' || nullif(btrim(new.respuestas->>'restriccion_detalle'), '') || '»', '') || '</li>';
  end if;
  if new.respuestas->>'sintomas' = 'Sí.' then
    v_alerta := v_alerta || '<li>Síntomas durante el esfuerzo' ||
      coalesce(': «' || nullif(btrim(new.respuestas->>'sintomas_detalle'), '') || '»', '') || '</li>';
  end if;

  v_asunto := 'Nueva solicitud ' || coalesce(v_prog.nombre, new.programa_id) ||
              ' — ' || coalesce(v_persona.nombre, 'sin nombre');

  v_html :=
    '<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;font-size:16px;line-height:1.6;color:#1E1D1A;max-width:520px">' ||
    '<h2 style="font-size:20px;margin:0 0 4px">' || coalesce(v_persona.nombre, 'Sin nombre') || '</h2>' ||
    '<p style="margin:0 0 18px;color:#56524A">' || coalesce(v_prog.nombre, new.programa_id) ||
      ' · ' || v_grupo ||
      coalesce(' · la invitó ' || nullif(btrim(new.referida_por), ''), '') || '</p>' ||
    coalesce(nullif(v_alerta, ''),
             '') ||
    case when v_alerta <> '' then
      '<div style="background:#F6E3E3;color:#7A2828;border-radius:10px;padding:14px 16px;margin:0 0 18px">' ||
      '<b>Revisar salud</b><ul style="margin:8px 0 0;padding-left:18px">' || v_alerta || '</ul></div>'
    else '' end ||
    coalesce('<p style="margin:0 0 18px">Teléfono: <b>' || nullif(btrim(v_persona.telefono), '') || '</b></p>', '') ||
    '<p style="margin:0"><a href="' || v_base || '/panel/?ficha=' || new.id::text ||
      '" style="display:inline-block;background:#1E1D1A;color:#FAF8F4;text-decoration:none;padding:12px 22px;border-radius:999px">Ver su ficha</a></p>' ||
    '</div>';

  select net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || v_clave),
    body    := jsonb_build_object(
                 'from', 'THRIVE <avisos@healingthroughmovement.studio>',
                 'to', jsonb_build_array(v_destino),
                 'subject', v_asunto,
                 'html', v_html)
  ) into v_pid;

  insert into public.avisos (inscripcion_id, destino, estado, peticion_id)
  values (new.id, v_destino, 'enviado', v_pid);

  return new;

exception when others then
  -- El aviso jamás tumba el insert. Se anota el error y la
  -- inscripción se guarda igual.
  begin
    insert into public.avisos (inscripcion_id, destino, estado, detalle)
    values (new.id, v_destino, 'error', left(sqlerrm, 400));
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists inscripciones_avisar on public.inscripciones;
create trigger inscripciones_avisar after insert on public.inscripciones
  for each row execute function public.avisar_inscripcion();


-- ══════════ 5 · CÓMO SE MIRA SI SALIÓ ══════════
-- El estado real de cada envío, cruzando el registro con la
-- respuesta que guardó pg_net.
create or replace view public.avisos_estado as
select
  a.id, a.creado_en, a.destino, a.estado, a.detalle,
  r.status_code,
  left(r.content, 300) as respuesta
from public.avisos a
left join net._http_response r on r.id = a.peticion_id
order by a.creado_en desc;

alter view public.avisos_estado set (security_invoker = on);
grant select on public.avisos_estado to authenticated;


-- ══════════ 6 · COMPROBACIÓN ══════════
--   select * from public.avisos_estado limit 10;   -- 200 = salió
