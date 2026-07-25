<h1 align="center">rig</h1>

<p align="center">
  <strong>Assemble an agent out of binaries you already have.</strong><br/>
  codex is the engine, <a href="https://pantalk.dev">pantalk</a> is the channel edge,
  <a href="https://mcpshim.dev">mcpshim</a> is the tool edge. rig wires them together and gets out of the way.
</p>

---

## What this is

Most agent products are one program that bundles everything — the loop, the
chat gateway, the tool registry, the memory — and ships a runtime to run it in.
rig is the other shape: a **distribution**. It contains no agent loop, no
provider SDK, and no vendored code. It generates each tool's native config,
supervises the daemons, and hands every process the same environment.

It is written in bash on purpose. If the integration surfaces are right — unix
sockets, JSON on stdout, `exec` — then a shell script is enough to assemble a
working agent, and nobody needs a library binding to do it. rig is the proof of
that claim, and it is small enough to read in one sitting.

```
        you                        chat platforms
         │                                │
    rig codex                        pantalkd  ── 13 connectors
         │                                │
         └──────────► codex ◄─────────────┘
                        │
                    mcpshimd  ── MCP servers, HTTP APIs
                        │
                  tool aliases on PATH
```

## Quick start

```bash
rig build                 # only if pantalk/mcpshim aren't installed
rig init --workdir ~/code
rig up
rig demo                  # end-to-end proof: inject a message, print the reply
rig codex                 # the local interface — codex's own CLI, wired to the cell
```

`rig demo` injects a message into a credential-free local bot and prints what
comes back. It needs no platform tokens, and if it prints a reply then the
whole chain works: pantalk → codex → pantalk.

## Commands

| | |
|---|---|
| `init [--force] [--workdir DIR]` | generate this cell's configs |
| `build` | build pantalk/mcpshim from an incubator checkout |
| `doctor` | check binaries, configs, daemons, config validity |
| `up` / `down` / `restart` | lifecycle |
| `status` | what's running |
| `logs [pantalk\|mcpshim] [-f]` | tail daemon logs |
| `reload` | reload both daemons' configs |
| `codex [args...]` | run codex inside the cell |
| `shell` | subshell wired to the cell |
| `env` | print the cell environment, eval-able |
| `demo [text]` | end-to-end check |
| `tools` / `call` | passthrough to mcpshim |
| `send` / `inject` / `stream` / `bots` / `history` | passthrough to pantalk |
| `cells` | list cells |

Passthroughs add the cell environment and nothing else. The tools keep their
own flags and their own JSON contract — rig never re-wraps them.

## Cells

A **cell** is the unit of separation. Both daemons resolve their socket,
config, and database purely from XDG environment variables, so a cell is
nothing more than a private XDG environment plus a private bindir on `PATH`:

```
XDG_RUNTIME_DIR  →  pantalk.sock, mcpshim.sock
XDG_CONFIG_HOME  →  pantalk/config.yaml, mcpshim/config.yaml
XDG_DATA_HOME    →  pantalk.db, mcpshim.db
PATH             →  mcpshim alias wrappers
```

That means no per-tool flags anywhere in rig, and it means cells cost nothing
to add:

```bash
rig --cell client-a init --workdir ~/work/client-a
rig --cell client-a up
rig --cell client-a codex
```

Each cell gets its own daemons, its own credentials, its own conversation
history, and its own tool aliases.

### Isolation

**Cells are instance separation, not a security boundary.** They run as the
same uid, so a process in one cell can reach another cell's socket by path if
it goes looking. What you get is independent state, independent credentials in
practice, and independent blast radius on crash.

The runtime directory is created `0700`, which keeps *other* uids out. For a
boundary that holds against a compromised or prompt-injected agent, run cells
under separate uids or in separate containers — the layout above is designed so
that change is a deployment decision, not a rewrite.

This matters because socket reachability *is* the authorization model: anything
that can reach `mcpshim.sock` can call every tool registered on it with its
credentials, and anything that can reach `pantalk.sock` can post as the bot on
every platform it's connected to.

## Adding a chat platform

The generated pantalk config ships one credential-free `local` bot. Add real
ones with pantalk's own tooling — rig doesn't wrap it:

```bash
rig shell
pantalk config add-bot --config "$XDG_CONFIG_HOME/pantalk/config.yaml" \
  --name team --type slack \
  --bot-token '$SLACK_BOT_TOKEN' --app-level-token '$SLACK_APP_LEVEL_TOKEN'
```

Then bind the `codex` agent to it under `agents:` and `rig reload`. See
[pantalk's agent docs](https://github.com/pantalk/pantalk) for `when:`
expressions, scheduled prompts, and per-channel routing.

## Adding tools

Register MCP servers or HTTP services in the cell's mcpshim config, then:

```bash
rig reload
rig up          # reinstalls alias wrappers into the cell bindir
rig tools
```

Tools reach codex as **plain shell commands on `PATH`**, not as MCP schemas in
the prompt. That's mcpshim's whole point — the context budget stays free for
work instead of tool definitions. The generated instructions tell codex to
discover them with `mcpshim tools`.

## Requirements

- `codex`, authenticated (`codex login`)
- `pantalk` + `pantalkd`, `mcpshim` + `mcpshimd` — or `rig build` with a Go
  toolchain and an incubator checkout
- `jq`, for `rig demo`

## Status

Proof of concept. It works end to end, and it is deliberately dumb where a real
orchestrator would not be: supervision is `nohup` plus a pidfile, there is no
restart backoff, no health probing, and no approval routing. Those absences are
the point — they mark exactly where bash stops being enough and a real
orchestrator has to begin.

## Known gaps

- **Approvals.** `approval_policy: never` and `sandbox: workspace-write` are
  baked in. Chat-originated permission prompts have nowhere to go, because a
  Slack thread cannot block on a y/n. A real orchestrator needs a policy engine
  here, not a prompt.
- **Sessions.** Pantalk keys conversations per user/channel/thread and codex
  keys threads; nothing joins them, so a conversation started in chat cannot be
  resumed in the terminal.
- **One engine.** Only the `codex` driver is generated. pantalk also has
  `claude` and `acp` drivers, and `acp` is the generic one worth targeting.
- **Alias staleness.** Wrappers are installed on `rig up`. Register a server
  mid-session and you need `rig reload && rig up`.
