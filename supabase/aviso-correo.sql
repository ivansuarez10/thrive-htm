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

-- ⚠️ Copia OCULTA del aviso (3 sep 2026). Va en `bcc` y no en `to` a
-- propósito: el aviso es de Denisse. Verlo dirigido a dos personas
-- cambia lo que el correo parece ser —de «tu aviso» a «un reporte del
-- sistema»— y además expone la otra dirección en cada mensaje.
--
-- La dirección va en la BASE y no acá: este repo es público.
--   update public.ajustes set correo_copia = 'tu@correo.com' where id = 1;
--   update public.ajustes set correo_copia = null where id = 1;   -- apagarla
--
-- NO se agrega al grant de anon ni a `ajustes_publicos`: los permisos de
-- esa tabla son por columna y listan una por una, así que nace privada.
alter table public.ajustes add column if not exists correo_copia text;

comment on column public.ajustes.correo_aviso is
  'A dónde llega el aviso de inscripción nueva. Vacío = no se manda.';
comment on column public.ajustes.correo_copia is
  'Copia oculta (bcc) del aviso. Vacío = solo va a correo_aviso. No se muestra en el panel: es un respaldo, no un ajuste de Denisse.';


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
  -- ⚠️ El `order by` no es adorno. Sin él, con dos secretos del mismo
  -- nombre Postgres devuelve cualquiera —y el 3 sep 2026 eso fue el
  -- primer sospechoso de un 401, porque el código lo permitía. Que gane
  -- siempre la más nueva.
  select decrypted_secret from vault.decrypted_secrets
  where name = 'resend_key' order by created_at desc limit 1;
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
  v_copia   text;
  v_persona record;
  v_prog    record;
  v_grupo   text;
  v_alerta  text := '';
  v_asunto  text;
  v_html    text;
  v_pid     bigint;
  v_base    text := 'https://healingthroughmovement.studio';
begin
  select correo_aviso, correo_copia into v_destino, v_copia from public.ajustes where id = 1;
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

  /* ══ El correo ══
     Rehecho el 3 sep 2026. El primero era una tarjeta blanca flotando
     sobre gris, con rótulos en versalitas y un botón píldora — o sea el
     lenguaje de una notificación de SaaS. Ivan: «que no parezca de chat
     gpt».

     THRIVE es lo contrario, y está escrito en el CLAUDE.md: «el resto
     del sitio no levanta nada del papel — son líneas finas, aire y
     tipografía». Acá tampoco: sin sombra, sin tarjeta, sin caja
     redondeada. Lo que separa son reglas de un píxel.

     Y el hilo de la marca es el serif en itálica, que NUNCA encabeza y
     sólo acompaña. Bodoni en el sitio; acá Georgia, que está en todos
     los clientes y es lo bastante Didone para sostener el gesto.

     ⚠️ El maquetado es de correo, no de web: tablas, estilos en línea,
     sin tipografías web. El <style> sólo lleva el modo oscuro y el
     ancho de teléfono — Apple Mail los respeta, que es donde Denisse
     lo abre; donde no, ya se ve bien con lo que trae en línea.
     La copia del original queda en 05-exploracion/aviso-correo.html
     para poder verla sin mandar un correo. */
  v_html :=
    '<!doctype html><html lang="es"><head><meta charset="utf-8">' ||
    '<meta name="color-scheme" content="light dark">' ||
    '<meta name="supported-color-schemes" content="light dark"><style>' ||
    '@media (prefers-color-scheme:dark){' ||
      '.papel{background:#141312!important}.tinta{color:#F1EEE9!important}' ||
      '.tinta2{color:#B3ADA4!important}.tinta3{color:#948E84!important}' ||
      '.regla{border-color:#302C29!important}.serif{color:#D8D2C9!important}' ||
      '.aviso{background:#7A4030!important}.aviso-t{color:#E8A48D!important}' ||
      '.boton{background:#2E9DB2!important}.boton a{color:#0F1717!important}}' ||
    '@media only screen and (max-width:620px){' ||
      '.caja{width:100%!important}.pad{padding-left:24px!important;padding-right:24px!important}' ||
      '.nom{font-size:32px!important}.col{display:block!important;width:100%!important}' ||
      '.col2{padding-top:18px!important}}' ||
    '</style></head><body class="papel" style="margin:0;padding:0;background:#FFFFFF">' ||

    -- La línea que se lee en la bandeja antes de abrir. Sin esto el
    -- cliente muestra el primer texto que encuentra, que no dice nada.
    '<div style="display:none;max-height:0;overflow:hidden;opacity:0">' ||
      coalesce(v_prog.nombre, new.programa_id) || ' &#183; ' || v_grupo ||
      case when v_alerta <> '' then ' &#183; con alerta de salud' else '' end ||
      '&#8203;&#847;&#8203;&#847;&#8203;&#847;&#8203;&#847;&#8203;&#847;&#8203;&#847;</div>' ||

    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="papel" style="background:#FFFFFF">' ||
    '<tr><td align="center"><table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" class="caja" style="width:560px;max-width:560px">' ||

    -- el sello. A 34 px el anillo de letras todavía se lee.
    '<tr><td class="pad" align="center" style="padding:44px 40px 0">' ||
      '<img src="' || v_base || '/assets/img/seal.svg" width="34" height="34" alt="Healing Through Movement" style="display:block;width:34px;height:34px"></td></tr>' ||

    -- el gesto de la marca
    '<tr><td class="pad" align="center" style="padding:20px 40px 0">' ||
      '<div class="serif tinta2" style="font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:17px;line-height:1.5;color:#56524A">' ||
      'Alguien más quiere entrenar con vos.</div></td></tr>' ||

    -- quién
    '<tr><td class="pad" align="center" style="padding:26px 40px 0">' ||
      '<div class="nom tinta" style="font-family:''Avenir Next'',''Segoe UI'',Helvetica,Arial,sans-serif;font-size:38px;line-height:1.1;letter-spacing:-1px;font-weight:600;color:#1E1D1A">' ||
      coalesce(v_persona.nombre, 'Sin nombre') || '</div>' ||
      '<div class="tinta2" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.5;color:#56524A;padding-top:10px">' ||
      coalesce(v_prog.nombre, new.programa_id) || ' &nbsp;&#183;&nbsp; ' || v_grupo ||
      coalesce(' &nbsp;&#183;&nbsp; la invitó ' || nullif(btrim(new.referida_por), ''), '') ||
      '</div></td></tr>' ||

    -- la alerta: regla al costado, no caja de color. Pesa por posición
    -- y por borde, no por gritar. Va ARRIBA de los datos porque es lo
    -- único que cambia lo que Denisse hace después.
    case when v_alerta <> '' then
      '<tr><td class="pad" style="padding:34px 40px 0">' ||
      '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>' ||
      '<td class="aviso" width="2" style="width:2px;background:#B5462F;font-size:0;line-height:0">&nbsp;</td>' ||
      '<td style="padding:2px 0 2px 18px">' ||
      '<div class="aviso-t" style="font-family:''Avenir Next'',''Segoe UI'',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;letter-spacing:.4px;color:#8A3A22;padding-bottom:6px">Revisar salud antes de agendar</div>' ||
      '<div class="tinta2" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#56524A"><ul style="margin:0;padding-left:18px">' ||
      v_alerta || '</ul></div></td></tr></table></td></tr>'
    else '' end ||

    -- los datos, sobre reglas de un píxel
    '<tr><td class="pad" style="padding:34px 40px 0">' ||
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">' ||
    '<tr><td class="regla" colspan="2" style="border-top:1px solid #E7E4DF;font-size:0;line-height:0">&nbsp;</td></tr><tr>' ||
    '<td class="col" width="50%" valign="top" style="padding:18px 16px 0 0">' ||
      '<div class="tinta3" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.4;color:#6E6961;padding-bottom:3px">Teléfono</div>' ||
      coalesce('<a href="tel:' || btrim(v_persona.telefono) || '" class="tinta" style="font-family:''Avenir Next'',''Segoe UI'',Helvetica,Arial,sans-serif;font-size:17px;font-weight:600;color:#1E1D1A;text-decoration:none">' || btrim(v_persona.telefono) || '</a>',
               '<span class="tinta3" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:15px;color:#6E6961">no lo dejó</span>') ||
      '</td>' ||
    '<td class="col col2" width="50%" valign="top" style="padding:18px 0 0 0">' ||
      '<div class="tinta3" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.4;color:#6E6961;padding-bottom:3px">Llegó</div>' ||
      '<div class="tinta" style="font-family:''Avenir Next'',''Segoe UI'',Helvetica,Arial,sans-serif;font-size:17px;font-weight:600;color:#1E1D1A">' ||
      to_char(now() at time zone 'America/Tegucigalpa', 'DD/MM') || ', ' ||
      trim(to_char(now() at time zone 'America/Tegucigalpa', 'HH12:MI am')) ||
      '</div></td></tr></table></td></tr>' ||

    -- una sola acción, sin sombra: la decisión de los botones del 29 ago
    '<tr><td class="pad" style="padding:36px 40px 0">' ||
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>' ||
    '<td class="boton" bgcolor="#17606F" style="background:#17606F;border-radius:999px">' ||
    '<a href="' || v_base || '/panel/?ficha=' || new.id::text ||
    '" style="display:inline-block;padding:15px 30px;font-family:''Avenir Next'',''Segoe UI'',Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none">Ver su ficha</a>' ||
    '</td></tr></table></td></tr>' ||

    '<tr><td class="pad" style="padding:16px 40px 0">' ||
    '<div class="tinta3" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:13px;line-height:1.55;color:#6E6961">' ||
    'Sus respuestas están en el panel. Por correo no viajan.</div></td></tr>' ||

    -- el pie: el lema de la casa, en el mismo serif
    '<tr><td class="pad" style="padding:44px 40px 0">' ||
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">' ||
    '<tr><td class="regla" style="border-top:1px solid #E7E4DF;font-size:0;line-height:0">&nbsp;</td></tr>' ||
    '<tr><td style="padding:22px 0 52px">' ||
    '<div class="serif tinta3" style="font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:15px;color:#6E6961;padding-bottom:10px">Move. Heal. Thrive.</div>' ||
    '<div class="tinta3" style="font-family:''Helvetica Neue'',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6E6961">' ||
    'Te llega porque alguien completó el formulario de THRIVE.<br>A dónde llega se cambia en el panel, en Ajustes.</div>' ||
    '</td></tr></table></td></tr>' ||

    '</table></td></tr></table></body></html>';

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
               || case when nullif(btrim(coalesce(v_copia,'')), '') is null then '{}'::jsonb
                       else jsonb_build_object('bcc', jsonb_build_array(btrim(v_copia))) end
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
