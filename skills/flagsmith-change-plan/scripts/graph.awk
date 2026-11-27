# Blast-radius walk over a TSV edge list: src<TAB>kind<TAB>dst<TAB>info
# Vars: start (node id), maxdepth (int), action, protected (0|1)
# Out:  N<TAB>depth<TAB>kind<TAB>dst<TAB>info  per reachable node (BFS order)
#       RISK<TAB>level<TAB>reason; reason; ...
BEGIN { FS = OFS = "\t"; if (maxdepth == "") maxdepth = 2 }
NF >= 3 {
  n = ++deg[$1]
  adj_k[$1, n] = $2; adj_d[$1, n] = $3; adj_i[$1, n] = $4
}
END {
  head = 1; tail = 1; queue[1] = start; depth[start] = 0; seen[start] = 1
  while (head <= tail) {
    u = queue[head++]
    if (depth[u] >= maxdepth) continue
    for (i = 1; i <= deg[u]; i++) {
      v = adj_d[u, i]; k = adj_k[u, i]
      cnt[k]++
      if (depth[u] == 0) direct[k]++
      print "N", depth[u] + 1, k, v, adj_i[u, i]
      if (!(v in seen)) { seen[v] = 1; depth[v] = depth[u] + 1; queue[++tail] = v }
    }
  }

  level = "LOW"; reasons = ""
  if (direct["noop"])               { level = "NOOP"; add("flag is already in the requested state") }
  else if (direct["experiment_running"]) { level = "BLOCKED"; add("a running experiment locks this flag") }
  else {
    if (protected == 1)             { up("MEDIUM"); add("protected environment") }
    if (direct["segment_override"] || direct["identity_overrides"])
                                    { up("MEDIUM"); add("overrides keep their own state (partial effect)") }
    if (direct["ci_gate"] && (action == "disable" || action == "archive"))
                                    { up("HIGH"); add(direct["ci_gate"] " CI gate(s) will fail") }
    if (direct["code_ref"] && action == "archive")
                                    { up("HIGH"); add("archiving a flag still referenced in code") }
    if (direct["code_ref"] && protected == 1)
                                    { up("HIGH"); add(direct["code_ref"] " code reference(s) in a protected environment") }
    if (cnt["co_located"])          add(cnt["co_located"] " co-located flag(s) to review")
    if (reasons == "")              add("no code, CI or override impact found")
  }
  print "RISK", level, reasons
}
function rank(l) { return l == "LOW" ? 1 : l == "MEDIUM" ? 2 : l == "HIGH" ? 3 : 4 }
function up(l)   { if (rank(l) > rank(level)) level = l }
function add(r)  { reasons = reasons (reasons == "" ? "" : "; ") r }
