// Doble de supabase-js para el test de la edge lawang-bot-proxy: auth.getUser, from('usuarios')...maybeSingle y rpc, contestados por globalThis.__sb.
export function createClient() {
  const sb = () => globalThis.__sb;
  return {
    auth: { getUser: async (jwt) => sb().getUser(jwt) },
    from: (t) => ({ select: () => ({ eq: () => ({ maybeSingle: async () => sb().ficha(t) }) }) }),
    rpc: async (nombre, args) => { sb().rpcs.push({ nombre, args }); return sb().rpc(nombre, args); },
  };
}
