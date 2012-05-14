#!/bin/bash
# 
#

source "${0%/*}/dependencies.sh";

perl -w ${0%/*}/nii2dt_batch.pl $*
