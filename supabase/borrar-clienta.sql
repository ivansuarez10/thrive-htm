-- ══════════════════════════════════════════════════════════════════
-- BORRAR UNA CLIENTA — 31 ago 2026
--
-- Ivan levantó a propósito, y sólo para este caso, la regla dura de
-- «acá no se borra». El motivo es real: Denisse tiene once clientas de
-- prueba estorbando, y «archivar» las manda a Former, que significa
-- ex-clienta. Once filas falsas ahí adentro ensucian una categoría que
-- sí quiere decir algo.
--
-- Lo que esta función NO deja hacer, y es lo que la vuelve segura:
--
--   · Sólo borra personas con es_clienta = true. Una candidata o una
--     inscrita no se puede borrar por acá ni por error ni a propósito.
--   · Sólo borra a quien NO tiene historial. Si tiene una inscripción,
--     un evento o un pago, se niega y dice por qué. Ese es exactamente
--     el caso que costó datos el 26 de agosto: alguien borrando lo que
--     creía que eran pruebas.
--   · La verificación vive en la BASE, no en el panel. Un botón se
--     puede saltar; esto no.
--
-- Las tres tablas que cuelgan de personas ya usan `on delete restrict`,
-- así que Postgres también se negaría solo. Esta función existe para
-- que el panel reciba un mensaje en español en vez de un error de
-- llave foránea, y para que el candado `personas_no_borrar` se levante
-- sólo dentro de esta transacción y para esta fila.
-- ══════════════════════════════════════════════════════════════════

create or replace function public.borrar_clienta(p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre  text;
  v_clienta boolean;
  v_ins int := 0;
  v_evt int := 0;
  v_pag int := 0;
begin
  select nombre, es_clienta into v_nombre, v_clienta
    from public.personas where id = p_id;

  if v_nombre is null then
    raise exception 'Esa clienta ya no está en la lista.';
  end if;

  if not coalesce(v_clienta, false) then
    raise exception 'Esto sólo borra clientas.'
      using hint = 'Las candidatas y las inscritas no se borran: se les cambia el estado.';
  end if;

  select count(*) into v_ins from public.inscripciones where persona_id = p_id;
  select count(*) into v_evt from public.eventos       where persona_id = p_id;
  if to_regclass('public.pagos') is not null then
    execute 'select count(*) from public.pagos where persona_id = $1' into v_pag using p_id;
  end if;

  if v_ins > 0 or v_evt > 0 or v_pag > 0 then
    raise exception '% tiene historial guardado y no se puede borrar.', v_nombre
      using hint = 'Movela a Former: su ficha se guarda y deja de estar a la vista.';
  end if;

  -- El candado se levanta acá adentro y sólo para esta transacción.
  perform set_config('app.borrar', 'si', true);
  delete from public.personas where id = p_id;

  return v_nombre;
end $$;

-- Sólo la sesión de Denisse. `anon` —o sea cualquiera con la clave
-- pública del sitio— no la puede llamar.
revoke all on function public.borrar_clienta(uuid) from public, anon;
grant execute on function public.borrar_clienta(uuid) to authenticated;
