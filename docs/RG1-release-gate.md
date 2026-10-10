# Mandatory Stylist release gate

No Release build is eligible for distribution until all four conditions are green:

1. Full iOS suite.
2. Worker suite, including every supported chat-version fixture, plus TypeScript. The current 1.5 and 1.6 fixtures are prepared compatibility fixtures, not authenticated captures of shipped payloads.
3. The signed Release `.app` contains `https://api.stylematchpro.com` as `STYLIST_CHAT_API_BASE_URL`.
4. The authorized live `/health/chat` endpoint reports `ok`.

The referenced gate script is prepared in the dirty iOS worktree but is untracked and not yet durable. Once it is reviewed and committed under a separate checkpoint, run it with explicit evidence inputs:

```sh
STYLEMATCH_RELEASE_APP=/path/to/StyleMatchAI.app \
STYLEMATCH_CHAT_HEALTH_URL=https://api.stylematchpro.com/health/chat \
STYLEMATCH_WORKER_ROOT=/path/to/STYLEMATCH_1_7_AI_STYLIST_WORKER \
./Scripts/rg1-release-gate.sh
```

The prepared script is designed to fail closed when an input or gate is missing and to print both repository HEADs plus a SHA-256 digest of its successful summary. RG1 requires `/health/chat`, but the route currently exists only in the dirty Worker worktree, is absent from committed canonical Worker HEAD and production, and requires an isolated commit plus separately authorized deployment. The cron and endpoint must be separately authorized and deployed before the live-health gate can become green.
