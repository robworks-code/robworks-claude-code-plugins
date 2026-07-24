#!/bin/sh
# The whole gate. Runs offline, needs nothing installed but node and python3.
#
# There is no CI on this repo on purpose: every check it would run is here, and
# a pre-push hook runs this with no wait for a remote runner. Add checks here,
# never in a workflow file.
#
# Each step's own exit code is captured, so a later step cannot mask an earlier
# failure and a trailing pipe cannot report success for a command that died.

cd "$(dirname "$0")/.." || exit 1
FAILED=""

note_failure() {
    printf 'FAIL: %s (exit %s)\n' "$1" "$2"
    FAILED="$FAILED$1; "
}

echo "=== marketplace.json parses ==="
python3 -c "
import json, sys
d = json.load(open('.claude-plugin/marketplace.json'))
plugins = d['plugins']
names = [p['name'] for p in plugins]
dupes = {n for n in names if names.count(n) > 1}
assert not dupes, 'duplicate plugin names: %s' % dupes
for p in plugins:
    for field in ('name', 'source', 'description', 'license', 'repository'):
        assert p.get(field), 'plugin %s is missing %s' % (p.get('name'), field)
    src = p['source']
    assert src.get('repo'), 'plugin %s has no source repo' % p['name']
print('ok: %d plugins, no duplicates, all required fields present' % len(plugins))
"
[ $? -eq 0 ] || note_failure "marketplace.json" $?

echo ""
echo "=== README table is current ==="
# Regenerate and require no diff. The table is generated, so a hand-edit or a
# marketplace.json change committed without re-running the generator is the
# failure this catches - it looks fine locally and is wrong on the web catalog.
node scripts/build-readme.js >/dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    note_failure "build-readme.js" $rc
elif ! git diff --quiet -- README.md; then
    echo "ERROR: README.md is out of date - scripts/build-readme.js changed it."
    echo "Commit the regenerated file."
    git --no-pager diff --stat -- README.md
    note_failure "README is stale" 1
else
    echo "ok: README table matches marketplace.json"
fi

echo ""
if [ -n "$FAILED" ]; then
    echo "VERIFY FAILED: $FAILED"
    exit 1
fi
echo "VERIFY PASSED"
