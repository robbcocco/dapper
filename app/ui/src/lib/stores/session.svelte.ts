/** Active server identity; set by the shell from `servers_list` / `server-changed`. */
export const session = $state<{ serverId: string | null }>({ serverId: null });
