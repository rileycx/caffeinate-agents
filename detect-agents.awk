# Input: ps -axww -o pid=,uid=,stat=,args=. Output: PID<TAB>agent.
# Match the executable or a known runtime entrypoint, never prompt substrings.
function basename(path) { sub(/^.*\//, "", path); return path }
function selected(name) { return name != "" && name in enabled }
function first_argument(name, position, option) {
    while (position <= NF) {
        option = $position
        if (name == "codex") {
            if (option ~ /^(--config|-c|--enable|--disable|--profile|-p|--cd|-C)$/) { position += 2; continue }
            if (option ~ /^(--config|--enable|--disable|--profile|--cd)=/ || option ~ /^(--no-daemon|--strict-config)$/) { position++; continue }
        }
        if (name == "claude" && option ~ /^(--dangerously-skip-permissions|--allow-dangerously-skip-permissions)$/) { position++; continue }
        break
    }
    return $position
}
BEGIN {
    n = split(names, list, /[[:space:]]+/)
    for (i = 1; i <= n; i++) enabled[list[i]] = 1
    n = split(extra, list, /[[:space:]]+/)
    for (i = 1; i <= n; i++) enabled[list[i]] = 1
}
$2 != user_id || $3 ~ /^[ZT]/ { next }
{
    executable = basename($4)
    agent = executable
    arg = 5
    # Native Cursor installs use a generic `agent` name: require its own path.
    if (executable == "agent" && $4 ~ /\/\.cursor\//) agent = "cursor-agent"
    if (executable ~ /^(node|bun|python[0-9.]*)$/) {
        entry = 5
        while ($entry ~ /^(--enable-source-maps|--no-warnings|--experimental-strip-types|-u|-B)$/ || $entry ~ /^--max-old-space-size=[0-9]+$/) entry++
        script = $entry
        arg = entry + 1
        agent = ""
        if (script ~ /\/@anthropic-ai\/claude-code\/cli\.js$/) agent = "claude"
        else if (script ~ /\/@openai\/codex\/bin\/codex\.js$/) agent = "codex"
        else if (script ~ /\/@google\/gemini-cli\/dist\/index\.js$/) agent = "gemini"
        else if (script ~ /\/@github\/copilot\/(index|cli)\.js$/) agent = "copilot"
        else if (script ~ /\/opencode-ai\/bin\/opencode$/) agent = "opencode"
        else if (script ~ /\/\.cursor\/.*\/index\.js$/) agent = "cursor-agent"
        else if (basename(script) ~ /^(claude|codex|gemini|opencode|copilot|aider|cursor-agent)$/) agent = basename(script)
        else if (executable ~ /^python/ && script == "-m" && $(entry + 1) == "aider") { agent = "aider"; arg = entry + 2 }
        else if (selected(executable)) agent = executable
    }
    if (!selected(agent)) next
    # Persistent infrastructure is not an active agent session. Only inspect
    # leading arguments: a prompt mentioning "app-server" must still match.
    first = first_argument(agent, arg)
    if (first ~ /^(--help|-h|--version|-V)$/) next
    if (agent == "codex" && first ~ /^(app-server|exec-server|mcp-server|mcp|login|logout|completion|update|doctor|remote-control|app|features)$/) next
    if (agent == "claude" && first ~ /^(daemon|gateway|remote-control|mcp|auth|install|update|doctor|setup-token)$/) next
    if (agent == "opencode" && first ~ /^(serve|web|mcp|auth|upgrade)$/) next
    printf "%s\t%s\n", $1, agent
}
