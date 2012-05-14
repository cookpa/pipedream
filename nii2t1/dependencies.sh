# Source the pipedream dependency file 
source ${0%/*}/../config/pipedream_config.sh

# Now check that everything is OK, and attempt to recover if not


# Look for Perl
if [[ `which perl 2> /dev/null` == "" ]] ; then
    echo "Cannot find Perl executable"
    return 1
fi

return 0

