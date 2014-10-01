#!/bin/bash
# 
# 
#
source "${0%/*}/dependencies.sh";

if [[ $? -gt 0 ]]; then
    exit 1
fi

perl -w ${0%/*}/dicom2series_batch.pl $*


