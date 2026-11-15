#!/bin/sh
set -eu
config=${1:-/opt/etc/nfqws2/nfqws2.conf}
mode=${2:---dry-run}
if [ "$mode" != --dry-run ] && [ "$mode" != --intercept=0 ]; then
    echo "Use --dry-run or --intercept=0" >&2
    exit 2
fi
. "$config"
set -f
if [ -n "$NFQWS_ARGS_IPSET" ]; then
    echo "This checker expects the explicit IP profiles of this package" >&2
    exit 2
fi
exec "${NFQWS2_BIN:-nfqws2}" "$mode" --qnum="$NFQUEUE_NUM" --user="$USER" \
    $NFQWS_BASE_ARGS $NFQWS_ARGS_CUSTOM --new \
    $NFQWS_ARGS_UDP --new \
    $NFQWS_ARGS_QUIC $NFQWS_EXTRA_ARGS --new \
    $NFQWS_ARGS $NFQWS_EXTRA_ARGS
