# Get a random number to avoid naming conflicts
RAN=$RANDOM

# Source the pipedream dependency file 
source ${0%/*}/../config/pipedream_config.sh

# Now check that everything is OK, and attempt to recover if not


# Sun Java stupidly prints version info on stderr
`${JAVAPATH}/java -version > /dev/null 2> /tmp/dicom2dt.$RAN`

if [[ `cat /tmp/dicom2dt.$RAN | grep HotSpot` == "" ]]; then
    
    `java -version > /dev/null 2> /tmp/dicom2dt.$RAN`
    
    if [[ `cat /tmp/dicom2dt.$RAN | grep HotSpot` == "" ]]; then
	echo "Cannot find Sun java executable"
	return 1
    fi

    echo "Cannot find Sun Java at Pipedream default path $JAVAPATH"
    echo "Using version on system path"

else
    # Need to modify PATH here, since Camino programs need 
    # to have Java on the PATH
    export PATH=$JAVAPATH:$PATH
fi

`rm -f /tmp/dicom2dt.$RAN`


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


# Look for ANTS
if [[ `which ${ANTSPATH}/ANTS 2> /dev/null` == "" ]] ; then
    
    if [[ `which ANTS 2> /dev/null` == "" ]] ; then
	echo "Cannot find ANTS executable"
	return 1
    fi

    echo "Cannot find ANTS at Pipedream default path $ANTSPATH"
    echo "Using version on system path"

    string=`which ANTS`
    export ANTSPATH=${string%ANTS} 

else
    export ANTSPATH
fi


# Look for GDCM
if [[ `${GDCMPATH}/gdcmdump` == "" ]] ; then
    
    if [[ `gdcmdump` == "" ]]; then 
	echo "Cannot find gdcm, unable to continue"
	return 1
    else
	echo "Cannot find gdcm at Pipedream default path $GDCMPATH"
	echo "Using version on system path"
	string=`which gdcmdump`
	export GDCMPATH=${string%/gdcmdump}
    fi
        

else
    export GDCMPATH
fi
 

if [[ `which  ${CAMINOPATH}/dtfit 2> /dev/null` == "" ]] ; then

    if [[ `which dtfit 2> /dev/null` == "" ]] ; then
	echo "Cannot find Camino bin dir"
	return 1
    fi

    echo "Cannot find Camino at Pipedream default path $CAMINOPATH"
    echo "Using version on system path"
  
    string=`which dtfit`
    export CAMINOPATH=${string%/dtfit}
    
else 
    export CAMINOPATH
fi


return 0
