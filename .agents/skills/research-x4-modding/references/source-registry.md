# X4 research source registry

Use every applicable row, in order. Record the URL/path, version or revision,
access date, and any access limitation. No source list can guarantee exhaustive
coverage; report channels that were unavailable instead of silently omitting
them.

| Channel | Route | Evidence use |
|---|---|---|
| Project | Repository code, tests, logs, and `docs/` | Integration context and local regressions; not proof of engine behavior by itself. |
| Installed game | `version.dat`, current catalogs, extracted Lua/MD/AI/XSD/assets, and named binary exports | `shipped-source`; export names alone do not establish signatures or semantics. |
| Installed extensions | Game-install and user-data `extensions/`, then Workshop copies | `third-party-technique`; record extension ID/version and file hash or upstream commit. Never commit the source. |
| Official Egosoft wiki | [Modding Support hub](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/), [Mission Director Guide](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/Mission%20Director%20Guide/), UI Lua overview, asset guides, Breaking Changes, X Tools documentation | `documented-public` when the current page directly supports the claim. Record page revision/modified date when visible. |
| Egosoft forums | [English X4 Scripts and Modding](https://forum.egosoft.com/viewforum.php?f=181), other language modding forums, and targeted `site:forum.egosoft.com` search | Lead by default, including staff posts; corroborate with shipped source, current official docs, or a live test. Direct automated access may hit the Anubis bot checkpoint, so record that limitation and use indexed results or user-provided permalinks. |
| Public mod sources | GitHub/GitLab upstream repositories, X4 Modding Wiki, Nexus descriptions/files, Steam Workshop descriptions/discussions | Lead or `third-party-technique`. Prefer upstream source plus release/version metadata. Download only with permission; inspect outside tracked paths. |
| Community discussion | Discord, Reddit, videos, comments, and private messages | Lead only. Discord requires user access/authority; request a permalink or transcript and record author/date. Never promote chat testimony without reproduction or stronger evidence. |
| Live game | Disposable save, Test Lab, build marker, debug log, and explicit matrix | `live-tested` only after reproduction with the conditions in `testing-experiments.md`. |

## External lookup procedure

1. Search the official wiki hub and its linked current guide before generic web
   search. Check Breaking Changes for version-sensitive UI or scripting work.
2. Search the English Egosoft modding forum directly and with a targeted web
   query. Search other language forums when the topic or mod author points there.
3. Search upstream repositories and current Nexus/Workshop pages for concrete
   implementations. Treat packaged or installed code as technique, not public API.
4. Use broader community channels only to find names, paths, calls, experiments,
   or authors that can be checked against higher-ranked evidence.
5. In the answer, list searched channels, unavailable channels, query/date, and
   the corroboration used for every community-derived conclusion.
