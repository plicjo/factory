NAME="factory"
MARKET="factory"
AUTHOR="Joshua Plicque"
GH_USER="plicjo"

cat > README.md <<EOF
# $MARKET

My agent workflow stack. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, at version $V (cursor/plugins@12d587d).
Diverged since; not a mirror.

Packaged as a Claude Code plugin. Grok Build reads the same format with no changes.

## Install

    claude plugin marketplace add $GH_USER/$MARKET
    claude plugin install $NAME@$MARKET

## Checking what upstream has done since

    ./upstream-log.sh
EOF

git add -A && git commit -m "port: claude code plugin manifests"
