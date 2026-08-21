/* Las cuentas de cobro dejan de vivir en contracts/assets/entities.js.
   Motivo (6-ago-2026): ese fichero se servia con 200 SIN login y ademas esta en
   el repo PUBLICO jvrcervantes-oss/lawang, legible en crudo desde el 27-jul.
   Unas coordenadas bancarias publicas son la materia prima de un fraude de
   transferencia, y un numero de cuenta no se rota como una contrasena.
   El repo se queda publico a proposito (de el depende el auto-deploy de
   Hostinger): lo que sale del repo son las cuentas, no el repo del hosting.
   SOCIEDADES se queda en el fichero: es la identidad que ya va impresa en todo
   contrato y factura que el comprador tiene en la mano. */
create table if not exists public.cuentas_bancarias (
  clave      text primary key,
  label      text not null,
  titular    text not null,
  banco      text not null,
  cuenta     text not null,
  codigo     text not null default '',
  direccion  text not null default '',
  -- jsonb y no text: hoy `extra` es a veces "", a veces "Tel: ..." y a veces
  -- {es,en,id} porque los contratos se imprimen en tres idiomas. jsonb conserva
  -- esa diferencia tal cual, asi que el objeto que llega al navegador es
  -- identico al que habia en el .js y bancoDocHTML no cambia.
  extra      jsonb not null default '""'::jsonb,
  orden      int  not null default 100,
  activa     boolean not null default true,
  creado_en  timestamptz not null default now()
);

alter table public.cuentas_bancarias enable row level security;

/* `using (true)` acotado a `authenticated` y NO es el patron prohibido del
   estandar (ese es el `USING(true)` sin rol, para que "el admin lo vea todo").
   Aqui no hay propiedad por fila que acotar: el agente elige cualquier cuenta al
   emitir, y el comprador necesita leer la de SU documento para poder pagar.
   Lo que importa es que `anon` se queda fuera. */
create policy "cuentas: solo con sesion" on public.cuentas_bancarias
  for select to authenticated using (true);

/* Nombrar los roles explicitamente: `revoke ... from public` NO basta en
   Supabase, porque anon/authenticated tienen sus propios GRANT y sobreviven
   (aprendido el 5-ago-2026). Sin escritura para nadie desde el navegador: las
   cuentas se tocan por SQL o desde una pantalla de admin server-side. */
revoke all on public.cuentas_bancarias from anon;
revoke all on public.cuentas_bancarias from authenticated;
grant select on public.cuentas_bancarias to authenticated;

comment on table public.cuentas_bancarias is
  'Cuentas de cobro de Lawang. FUENTE UNICA: salieron de contracts/assets/entities.js el 6-ago-2026 porque ese fichero es publico (web sin login + repo publico de GitHub). Solo lectura y solo con sesion.';;
