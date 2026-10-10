// Doble de supabase-js para portal_enlace.test.js (LAW-1 S2): todo lo que las edges portal-acceso y portal-invitar piden a la
// base y a Auth lo contesta globalThis.__sb, y cada llamada queda anotada en __sb.traza (para comprobar qué se llamó y en qué orden).
// La base NO pasa por fetch: así «no se llamó a fetch» en el test significa «no salió ningún correo».
function consulta(tabla, clave) {
  const q = { tabla, clave, op: 'select', campos: '', filtros: [], fila: null };
  const corre = () => globalThis.__sb.consulta(q);
  const b = {
    select(c) { q.campos = c; return b; },
    eq(c, v) { q.filtros.push(['eq', c, v]); return b; },
    in(c, v) { q.filtros.push(['in', c, v]); return b; },
    limit(n) { q.limite = n; return b; },
    update(f) { q.op = 'update'; q.fila = f; return b; },
    upsert(f, o) { q.op = 'upsert'; q.fila = f; q.opciones = o; return b; },
    maybeSingle() { q.unica = true; return Promise.resolve(corre()); },
    then(res, rej) { return Promise.resolve(corre()).then(res, rej); },
  };
  return b;
}

export function createClient(_url, clave, opciones) {
  const sb = () => globalThis.__sb;
  const anota = (que, args) => { sb().traza.push({ que, args, clave }); };
  return {
    rpc: async (nombre, args) => { anota('rpc:' + nombre, args); return sb().rpc(nombre, args, { clave, opciones }); },
    from: (tabla) => { anota('from:' + tabla); return consulta(tabla, clave); },
    auth: {
      getUser: async (jwt) => { anota('auth.getUser'); return sb().getUser(jwt); },
      signInWithOtp: async (a) => { anota('auth.signInWithOtp', a); return { error: { message: 'no debe usarse' } }; },
      admin: {
        listUsers: async (a) => { anota('admin.listUsers', a); return sb().listUsers(a); },
        createUser: async (a) => { anota('admin.createUser', a); return sb().createUser(a); },
        updateUserById: async (id, a) => { anota('admin.updateUserById', { id, ...a }); return sb().updateUserById(id, a); },
        generateLink: async (a) => { anota('admin.generateLink', a); return sb().generateLink(a); },
      },
    },
  };
}
