# Source the pipedream dependency file 
source ${0%/*}/../config/pipedream_config.sh

# Now check that everything is OK, and attempt to recover if not


# Look for Perl
if [[ `which perl 2> /dev/null` == "" ]] ; then
    echo "Cannot find Perl executable"
    return 1
fi

if [[ `${GDCMPATH}/gdcmdump | grep gdcmdump` == "" ]] ; then
    
    if [[ `gdcmdump | grep gdcmdump` == "" ]]; then 
	echo "Cannot find GDCM executables"
        return 1
    fi

    echo "Cannot find GDCM at Pipedream default path $GDCMPATH"
    echo "Using version on system path"
    string=`which gdcmdump`
    export GDCMPATH=${string%/gdcmdump}

else
    export GDCMPATH
fi
 

return 0


