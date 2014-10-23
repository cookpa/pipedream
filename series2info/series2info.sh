#!/bin/bash
#
# Sets all necessary environment variables, then calls series2info.pl
#
source "${0%/*}/dependencies.sh";
ulimit -c 0

if [[ $? -gt 0 ]]; then
    exit 1
fi

perl -w ${0%/*}/series2info.pl "$@"
