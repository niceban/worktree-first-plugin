# IMPL-103 Summary: doctor.sh staleness改用last_active_at

## Task ID
IMPL-103

## Status
completed

## Affected Files
- **Modified**: `scripts/doctor.sh`

## Changes Made

### scripts/doctor.sh

**Problem**: Lines 45-53 used `git log -1 --format=%ct` (git commit time) for staleness check, which doesn't reflect actual user activity.

**Solution**: Changed staleness check to use `last_active_at` from metadata JSON:

1. Extract slug from worktree path: `slug=$(basename "$path")`
2. Build metadata file path: `${REPO_DIR}/.worktree-first/worktrees/${slug}.json`
3. If metadata exists, read `last_active_at` field with jq
4. Parse date string to unix timestamp (handles both Linux and macOS/Darwin)
5. Fall back to git commit time if:
   - Metadata file doesn't exist
   - `last_active_at` field is missing/empty
   - Date parsing fails

**Key code change**:
```bash
# Staleness check: Use metadata last_active_at if available, fallback to git commit time
last_ts=0
slug=$(basename "$path")
meta_file="${REPO_DIR}/.worktree-first/worktrees/${slug}.json"

if [[ -f "$meta_file" ]]; then
  last_active=$(jq -r '.last_active_at // empty' "$meta_file" 2>/dev/null || echo "")
  if [[ -n "$last_active" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      last_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_active" +%s 2>/dev/null || echo 0)
    else
      last_ts=$(date -d "$last_active" +%s 2>/dev/null || echo 0)
    fi
  fi
fi

# Fallback to commit time if metadata missing or failed to parse
if [[ "$last_ts" -eq 0 ]]; then
  last_ts=$(git log -1 --format="%ct" "$head" 2>/dev/null || echo "0")
fi
```

## Verification
- [x] doctor.sh exists
- [x] bash -n syntax check passed
- [x] Handles Darwin (macOS) and Linux date formats
- [x] Backward compatible (no metadata = fallback to commit time)

## Notes
- Staleness threshold remains 7 days
- Metadata must exist in `.worktree-first/worktrees/<slug>.json` format
- ISO 8601 format expected for `last_active_at` field
