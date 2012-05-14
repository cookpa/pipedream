#!/bin/bash
# 
# Sets all necessary environment variables, then calls Perl
#
source "${0%/*}/dependencies.sh";

if [[ $? -gt 0 ]]; then
    exit 1
fi

perl -w ${0%/*}/dicom2nii_batch.pl $*
