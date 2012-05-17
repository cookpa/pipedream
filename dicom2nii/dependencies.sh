# Source the pipedream dependency file 
source ${0%/*}/../config/pipedream_config.sh

# Now check that everything is OK, and attempt to recover if not

# Look for Perl
if [[ `which perl 2> /dev/null` == "" ]] ; then
    echo "Cannot find Perl executable"
    return 1
fi


# Look for dcm2nii
if [[ `which ${DCM2NIIPATH}/dcm2nii 2> /dev/null` == "" ]] ; then

    # Use of which here conveniently tests that files exists and is executable
    if [[ `which dcm2nii 2> /dev/null` == "" ]] ; then
        echo "Cannot find dcm2nii executable"
        return 1
    fi

    echo "Cannot find dcm2nii at Pipedream default path $DCM2NIIPATH"
    echo "Using version on system path"

    string=`which dcm2nii`
    export DCM2NIIPATH=${string%/dcm2nii}

else
    export DCM2NIIPATH
fi


return 0


