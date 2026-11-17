# Go Forge R4 — code at memory speed

[![Competition](https://make.fun/badge/github-core-clone-01.svg)](https://make.fun/bounty/github-core-clone-01)
[![Rank](https://make.fun/badge/github-core-clone-01/RenaldiRenaldi/github-core-clone-01-r4/rank.svg)](https://make.fun/bounty/github-core-clone-01)
[![Reward](https://make.fun/badge/github-core-clone-01/RenaldiRenaldi/github-core-clone-01-r4/reward.svg)](https://make.fun/bounty/github-core-clone-01)

A native Go entry for [Build a GitHub-compatible git forge](https://make.fun/bounty/github-core-clone-01). R4 reimplements the forge from scratch: Git object storage, smart HTTP, GitHub-shaped REST, GraphQL and MCP share one in-memory domain model. It does not invoke git, databases or external services. The included Linux amd64 executable is statically linked and under 8 MiB. `main.ts` only launches it; the Go process owns registration, HTTP and shutdown.

## Run and verify

```sh
# Go 1.24 or later; no third-party modules
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o forge .
PORT=39041 MAKEFUN_SHOP_TOKEN=forge-demo node main.ts
# Another terminal (curl and git are demo tools, not server dependencies)
./demo.sh
go test ./...
go test -race ./...
go test -bench . -run '^$'
mkdir -p out
MAKEFUN_OUTPUT_DIR=out node main.ts
```

The demo performs REST create → real Git clone → branch → commit → push → branch protection → PR → approval → squash merge → fetch → read merged bytes → UI. Use a fresh server for each demo. Offline mode writes `out/forge.json`, a deterministic object proof containing two divergent branches and their actual three-way merge. All timestamps and commit signatures are deterministic. Under `MAKEFUN_ENV_URL`, Go binds port 0, registers it, polls `/done`, and exits cleanly. It never needs a Go compiler in the grading container.

## Measured results

2026-11-17, Linux amd64, AMD EPYC 9D25 host, Go 1.24.0, GOMAXPROCS=4. These are measurements, not promised production capacity. Handler microbenchmarks use `httptest.ResponseRecorder`; TCP benchmarks use a real loopback HTTP server and sequential keep-alive requests, including client overhead. Clone here means a cached fetch of a three-object small repository, not spawning a git executable.

| Read path | Handler latency | Sequential TCP latency | TCP requests/sec |
|---|---:|---:|---:|
| GET repository | 1.931 µs | 70.345 µs | 14,216 |
| GET v2 refs advertisement | 0.764 µs | 61.066 µs | 16,376 |
| Cached small-repo fetch/clone | 2.632 µs | 79.083 µs | 12,645 |

Kit process-driver grading, three practice draws: **120/120 checks in every draw, scores 991 / 985 / 982, mean 986/1000**, all replay exports byte-identical. `perf_p50_us` mean: 241,814. The driver runs Node 24.22.1; the kit records production Node 26.13.1, so these are local results. No transcript bundle was supplied to these runs: authorship/eligibility remains the parent's bundle check, not a passed claim here.

A same-host R3 comparison passed the same checks at 984/1000. Workload p50 totals (not individual-request latency):

| Workload | R3 TypeScript | R4 Go |
|---|---:|---:|
| 200 pushes | 749.057 ms | 470.929 ms |
| 50 concurrent shallow clones | 88.173 ms | 89.049 ms |
| 2,000 issue reads | 662.587 ms | 576.700 ms |
| 200 issue writes | 83.002 ms | 97.893 ms |

R4 improves pushes and reads in this comparison; clone is effectively similar and writes were slower. Host noise and suite-client overhead matter. This is evidence of improvement, not proof of a leaderboard rank.

## Why this engine is different

* Immutable SHA-1 objects and repository locks keep ref validation and publication in one transaction. Compressed push packs stream from `io.Reader`; only inflated quarantined objects are retained. Checksums, declared sizes, delta bounds and graph connectivity are checked before publishing. Both ofs-delta and ref-delta work, including thin-pack bases already in the repository.
* `sync.Pool` reuses best-speed zlib writers. Version-invalidated serialized repository/issue responses and bounded fetch caches remove repeat JSON encoding and pack compression. Immutable commit ancestry has a bounded cache. No disk access occurs on request paths.
* Pushes compare the client's old SHA, reject non-fast-forward branches, non-commit branch targets, invalid names, duplicate refs and namespace collisions. `atomic` rejects the entire group; without it, valid refs can succeed independently. Failed packs do not publish their objects.
* Merges compute the common ancestor, then compare ancestor/base/head entries. Independent base changes survive; conflicting edits and file/directory collisions block. Squash commits parent the current base; merge commits parent both tips. Reviews bind to a head SHA, latest reviews supersede older opinions, stale reviews can be ignored, and protected branches require approvals. REST merge accepts expected `sha`.

## API guide

All `/api/*` and `/mcp` requests require `Authorization: Bearer $MAKEFUN_SHOP_TOKEN` (local default `forge-demo`). Git also accepts Basic auth with the token as password. Private Git repositories require auth. REST errors are JSON `{message}`, and responses carry `X-GitHub-Request-Id`.

```sh
BASE=http://127.0.0.1:39041
curl -H 'Authorization: Bearer forge-demo' -H 'content-type: application/json' \
  -d '{"name":"hello","auto_init":true}' "$BASE/api/v3/user/repos"
curl -H 'Authorization: Bearer forge-demo' \
  "$BASE/api/v3/repos/adaiversen/hello"
```

| Endpoint | Methods and behavior |
|---|---|
| `/healthz` | GET liveness JSON, public |
| `/api/v3/`, `/api/v3/meta`, `/api/v3/user` | GET root/scopes, installed version, authenticated viewer |
| `/api/v3/user/repos` | GET paginated list (`page`, `per_page`); POST create (`name`, `description`, `private`, `auto_init`) |
| `/api/v3/users/{owner}/repos`, `/api/v3/orgs/{owner}/repos` | GET list; POST create under owner |
| `/api/v3/repos/{owner}/{repo}` | GET; PATCH description; DELETE |
| `…/contents/{path}` | GET file/base64 or directory (`ref`); PUT base64 `content`, `message`, optional `branch`, expected blob `sha`; DELETE with expected `sha` |
| `…/labels` | GET; POST `name`, `color` |
| `…/issues` | GET (`state`, `direction`); POST `title`, `body`, known `labels` |
| `…/issues/{n}` | GET; PATCH `title`, `body`, `state` |
| `…/issues/{n}/comments` | GET; POST `body` |
| `…/pulls` | GET (`state`); POST `title`, `body`, `head`, `base` |
| `…/pulls/{n}` | GET; PATCH state/title/body |
| `…/pulls/{n}/files` | GET changed-file metadata and patch |
| `…/pulls/{n}/merge` | PUT optional `sha`, `merge_method: squash|merge` |
| `…/pulls/{n}/reviews` | GET; POST `event: APPROVE|REQUEST_CHANGES|COMMENT`, optional `commit_id`, `body` |
| `…/pulls/{n}/reviews/{id}/dismissals` | PUT dismiss review |
| `…/branches`, `…/branches/{name}`, `…/tags` | GET branches/tags with target SHA |
| `…/branches/{name}/protection` | GET; PUT settings; DELETE |
| `…/commits`, `…/commits/{sha}` | GET history (`sha` query) or commit |
| `…/git/refs`, `…/git/refs/{path}`, `…/git/ref/{path}` | GET; POST create; PATCH update; DELETE |
| `…/git/blobs` and `…/git/blobs/{sha}` | POST bytes (`encoding: base64` or text); GET |
| `…/git/trees` and `…/git/trees/{sha}` | POST entries with optional `base_tree`; GET recursive files |
| `…/git/commits` and `…/git/commits/{sha}` | POST tree/parents/message; GET |
| `…/events` | GET empty event list (history persistence is not implemented) |
| `/api/v3/search/issues?q=text` | GET title substring search |

Smart HTTP: `/{owner}/{repo}.git/info/refs?service=git-upload-pack|git-receive-pack`, POST `git-upload-pack`, POST `git-receive-pack`. Upload supports v0 and v2 `ls-refs`/`fetch`, shallow depth, tag peeling, `blob:none`, `blob:limit=N`, sideband framing and incremental haves. Receive is v0 with report-status, delete-refs, side-band-64k, ofs-delta and atomic.

GraphQL: POST `/api/graphql` with `{query,variables}` or an array of operations. Supports aliases, input objects, enum lists, variables, selections, issue cursor pagination and schema feature probes. Queries: viewer, repository, node, search, __type. Mutations: createIssue, closeIssue, addComment, createPullRequest, mergePullRequest. This is a compact parser for the supported schema, not a full GraphQL specification implementation.

```sh
curl -H 'Authorization: Bearer forge-demo' -H 'content-type: application/json' \
  -d '{"query":"{ repository(owner:\"adaiversen\", name:\"hello\") { id name issues(first:10) { nodes { number title state } } } }"}' \
  "$BASE/api/graphql"
```

MCP: POST `/mcp`, JSON-RPC 2.0, modern `server/discover` (2026-07-28) or legacy `initialize` (2025-11-25), `tools/list`, `tools/call`. Tools: `create_repo`, `get_repo`, `create_issue`, `list_issues`, `create_pull_request`, `merge_pull_request`, `review_pull_request`, `get_file_contents`. Every tool uses the same REST/domain store and preserves request IDs.

```sh
curl -H 'Authorization: Bearer forge-demo' -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_issue","arguments":{"owner":"adaiversen","repo":"hello","title":"Measured, not guessed"}}}' \
  "$BASE/mcp"
```

Optional read-only UI: `/` lists public repositories, `/{owner}/{repo}` shows files, history and issues, `/{owner}/{repo}/blob/{ref}/{path}` renders escaped file bytes. The grading client needs no UI.

## Scope and limits

All state is ephemeral. The local viewer is `adaiversen`; this is a single-token forge, not multi-user identity management. The API is deliberately scoped: no full GraphQL validation, persistent event log, line-level text merge, Git LFS, SSH, rebase merge or durable storage. Pack/request limits bound compressed input and individual inflated objects, not total lifetime memory. Caches are bounded per repository by entry count; fetch entries are also size-limited. Review approvals reflect the one authenticated user. The static binary targets Linux amd64; rebuild for other platforms.

MIT licensed. Built freshly in the anchored R4 session; R3 was read for behavior only. No competition submission is performed by this repository or this session.
