function parse(raw) {
  if (typeof raw !== "string" || raw.length > 1048576) throw new Error("Invalid status size");
  var data = JSON.parse(raw);
  if (data.version !== 1 || !Array.isArray(data.hosts) || data.hosts.length > 256)
    throw new Error("Invalid SSH status");
  var seen = {};
  var hosts = data.hosts.map(function(host) {
    if (!host || typeof host.host !== "string" ||
        !/^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,252}$/.test(host.host) || seen[host.host])
      throw new Error("Invalid SSH alias");
    seen[host.host] = true;
    if (!Array.isArray(host.aliases) || host.aliases.length > 256 ||
        host.aliases.some(function(alias) {
          return typeof alias !== "string" || !/^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,252}$/.test(alias);
        })) throw new Error("Invalid SSH aliases");
    if (["open", "closed", "unknown", "unavailable"].indexOf(host.state) < 0 ||
        ["master-only", "direct", "mixed"].indexOf(host.policy) < 0 ||
        (host.sessions !== null && (!Number.isInteger(host.sessions) || host.sessions < 0)))
      throw new Error("Invalid SSH state");
    return {
      host: host.host, aliases: host.aliases, state: host.state,
      sessions: host.sessions, policy: host.policy,
      destination: String(host.destination || "").slice(0, 512),
      error: String(host.error || "").slice(0, 2000)
    };
  });
  if (!Array.isArray(data.errors) || data.errors.length > 256) throw new Error("Invalid errors");
  return { hosts: hosts, errors: data.errors.map(function(error) { return String(error).slice(0, 2000); }) };
}

function plainTooltip(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
