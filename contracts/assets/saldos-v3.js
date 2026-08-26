/* ═══════════════════════════════════════════════════════════════════════════
   SALDOS v3 · nombre y pendiente donde el cliente ya mira — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   ENCARGO. El cliente dice que le falta ver «los datos más importantes:
   nombres y balances pendientes de pago». Auditadas las siete pantallas con
   datos, el dato existe y Vencimientos ya lo enseña bien — el problema es que
   no está donde entra a mirar:

     Contratos ..... comprador sí, pendiente NO (solo el precio)
     Compradores ... la lista de personas, y ni una cifra de dinero
     Proyectos ..... ni comprador ni pendiente: solo el precio de la unidad
     Obra .......... sin comprador

   QUÉ NÚMERO (decisión del owner): el PENDIENTE TOTAL de la operación, con la
   parte ya VENCIDA marcada en rojo. Ni solo lo vencido —un comprador con
   200.000 € por pagar saldría a cero si aún no le toca— ni dos columnas, que
   en un móvil plegado no caben.

   POR QUÉ ESTO Y NO TOCAR LAS CUATRO HERRAMIENTAS. El cálculo del dinero ya
   vive en `operaciones-cuentas.js` y lo comparten el panel, Operaciones y su
   v3. Meterlo a mano en cuatro pantallas más serían cinco sitios donde el mismo
   número puede empezar a decir cosas distintas. Aquí se calcula UNA vez y se
   inyecta en la tabla ya pintada, igual que la paginación automática: la
   herramienta no se entera.

   CÓMO SE ATA CADA FILA A SU DINERO. Por el número de contrato, que ya está
   impreso en la fila de Contratos, Proyectos y Obra. Compradores no lo tiene,
   así que va por email o pasaporte, que es como los ata la propia base
   (`contrato_compradores` → `clients`). Lo que no se pueda atar se queda con un
   guion: un cero inventado en una columna de dinero es peor que un hueco.
   ═══════════════════════════════════════════════════════════════════════════ */
(function(){
'use strict';
if(window.LW_SALDOS) return;

var HOY = new Date().toISOString().slice(0, 10);
var estado = { listo:false, cargando:false, porNumero:{}, porPersona:{}, error:null };

function suma(mapa, clave, campo, valor){
  if(!mapa[clave]) mapa[clave] = { pendiente:0, vencido:0, moneda:'EUR', nombre:'', contratos:[] };
  mapa[clave][campo] += valor || 0;
}

async function cargar(SB){
  if(estado.listo || estado.cargando) return estado;
  estado.cargando = true;
  try{
    /* Se reusa el MISMO cargador que Operaciones: mismas consultas, mismos
       topes, mismo aviso si recorta. Lo único que se pide aparte es lo que
       queda por cobrar de cada factura, que es de facturas y no de contratos. */
    var r = await lwOperacionesCargar(SB, function(){});
    var pend = await SB.rpc('facturas_pendiente_equipo');
    var porFactura = {};
    (pend.error ? [] : (pend.data || [])).forEach(function(x){
      porFactura[x.factura_id] = Number(x.pendiente) || 0;
    });

    r.ops.forEach(function(o){
      /* `cuentaGrupo` y no `cuenta`: parcela y construcción del mismo comprador
         son UNA venta. Se calcula sobre la raíz para no contarla dos veces, y
         se indexa por el número de CADA contrato del grupo, que es lo que sale
         impreso en la fila de cada herramienta. */
      if(o.padre) return;
      var c = cuentaGrupo(o);
      var grupo = [o].concat(o.hijos || []);
      /* Vencido: lo que queda por cobrar de las facturas del grupo cuya fecha
         de vencimiento ya pasó. Un recibí no vence y una anulada no existe. */
      var vencido = 0;
      grupo.forEach(function(g){
        (g.facturas || []).forEach(function(f){
          if(f.anulada || f.tipo === 'recibi' || !f.venc || f.venc >= HOY) return;
          var p = porFactura[f.id] != null ? porFactura[f.id] : (Number(f.total) || 0);
          if(p > 0.005) vencido += p;
        });
      });
      /* Lo vencido no puede pasar del pendiente: si una factura vieja sigue
         abierta pero la operación ya se cobró por otra vía, decir que se debe
         más de lo que se debe es peor que no decir nada. */
      var pendiente = (c.pendiente != null && c.pendiente > 0) ? c.pendiente : 0;
      if(vencido > pendiente) vencido = pendiente;

      var ficha = { pendiente:pendiente, vencido:vencido, moneda:c.moneda || 'EUR',
                    comprador:o.comprador_nombre || '', sinPrecio:!c.precio };
      grupo.forEach(function(g){ if(g.numero) estado.porNumero[g.numero] = ficha; });

      /* Por persona: se ata por email y pasaporte, que es como los une la base.
         Una persona con dos operaciones suma las dos — que es justo la cifra
         que hoy no existe en ningún sitio. */
      grupo.forEach(function(g){
        (g.compradores || []).forEach(function(v){
          var cl = v.clients; if(!cl) return;
          [cl.email, cl.passport_number].forEach(function(k){
            if(!k) return;
            k = String(k).trim().toLowerCase();
            if(!k) return;
            if(!estado.porPersona[k]) estado.porPersona[k] =
              { pendiente:0, vencido:0, moneda:ficha.moneda, nombre:cl.full_name || '', contratos:[] };
            /* Un grupo se suma UNA vez por persona aunque tenga tres contratos
               y la persona esté en los tres. */
            if(estado.porPersona[k].contratos.indexOf(o.id) < 0){
              estado.porPersona[k].contratos.push(o.id);
              estado.porPersona[k].pendiente += ficha.pendiente;
              estado.porPersona[k].vencido   += ficha.vencido;
            }
          });
        });
      });
    });
    estado.listo = true;
  }catch(e){
    estado.error = e && e.message;
    console.warn('saldos-v3:', estado.error);
  }
  estado.cargando = false;
  return estado;
}

/* El texto de una celda de dinero. Nunca un cero cuando no se sabe: `null`
   significa «no se ha podido atar esta fila», y eso se dice con un guion. */
function celda(f){
  if(!f) return '<span class="v3-saldo-mudo">—</span>';
  if(f.sinPrecio && !f.pendiente) return '<span class="v3-saldo-mudo">sin precio</span>';
  if(f.pendiente <= 0.005) return '<span class="v3-saldo-ok">Cobrado</span>';
  var txt = '<span class="v3-saldo">' + lwFormatoImporte(f.pendiente, f.moneda) + '</span>';
  if(f.vencido > 0.005){
    txt += '<span class="v3-saldo-venc">' + lwFormatoImporte(f.vencido, f.moneda) + ' vencido</span>';
  }
  return txt;
}

window.LW_SALDOS = {
  cargar: cargar,
  celda: celda,
  porNumero: function(n){ return n ? estado.porNumero[String(n).trim()] || null : null; },
  porPersona: function(k){ return k ? estado.porPersona[String(k).trim().toLowerCase()] || null : null; },
  get listo(){ return estado.listo; },
  get error(){ return estado.error; }
};
})();
