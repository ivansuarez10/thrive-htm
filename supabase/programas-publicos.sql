-- ═══════════════════════════════════════════════════════════
--  HTM — lo que el SITIO puede leer de los programas
--
--  Para que la landing muestre los precios y horarios que Denisse
--  configura en el panel, el público tiene que poder leerlos. Hoy
--  no puede: `programas` no tiene política para anon y devuelve [].
--
--  Y `ajustes_publicos` ya no alcanza: precio_2x, precio_3x, hora y
--  dias_* quedaron en NULL cuando el 27 de agosto los precios se
--  mudaron a programas.ajustes.grupos, uno por programa. La vista
--  seguía existiendo con las columnas vacías, que es la peor forma
--  de quedar obsoleta: no falla, devuelve null.
-- ═══════════════════════════════════════════════════════════

-- Solo lo que ya está impreso en la landing. Nada de estados,
-- rutas internas ni la lista de clases de prueba: quién viene a
-- qué hora es de Denisse, no del público.
create or replace view public.programas_publicos as
select
  id,
  nombre,
  subtitulo,
  ajustes->>'hora'                   as hora,
  (ajustes->>'cupos_por_grupo')::int as cupos_por_grupo,
  ajustes->>'periodo_inicio'         as periodo_inicio,
  ajustes->>'periodo_fin'            as periodo_fin,
  coalesce(ajustes->'grupos', '[]'::jsonb) as grupos,
  orden
from public.programas
where activo and not provisional;

alter view public.programas_publicos set (security_invoker = on);
grant select on public.programas_publicos to anon, authenticated;

-- security_invoker devuelve la consulta contra la tabla con los
-- permisos de quien pregunta, así que anon necesita su política.
-- Se limita a los activos y NO provisionales: un programa a medio
-- definir no tiene por qué asomarse al público.
drop policy if exists "el sitio lee los programas publicados" on public.programas;
create policy "el sitio lee los programas publicados"
  on public.programas for select to anon
  using (activo and not provisional);

-- ⚠️ Y los permisos de COLUMNA, por la misma razón que en `ajustes`:
-- la RLS filtra filas, no columnas. Sin esto, anon con la política de
-- arriba podría leer `estados`, `ruta_form` y todo lo demás de los
-- programas publicados. Hoy no es secreto; el problema es la columna
-- privada que alguien agregue mañana.
revoke all on public.programas from anon;
grant select (id, nombre, subtitulo, ajustes, orden, activo, provisional)
  on public.programas to anon;

-- ══════════ COMPROBACIÓN ══════════
--   select * from public.programas_publicos;
-- Y con la clave anon: `programas` completo debe dar 42501 en las
-- columnas no otorgadas, y `programas_publicos` debe devolver THRIVE.
