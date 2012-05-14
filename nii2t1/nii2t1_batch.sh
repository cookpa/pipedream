#!/bin/bash
# 
# Sets all necessary environment variables, then calls dicom2dt.pl
#
source "${0%/*}/dependencies.sh";

if [[ $? -gt 0 ]]; then
    exit 1
fi

perl -w ${0%/*}/nii2t1_batch.pl $*
