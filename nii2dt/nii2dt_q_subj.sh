# Wrapper script for sending nii2dt.sh to the queue
#
# args: ${NII2DT_DIR} $HOME $BVAL $BVEC $TEMPLATE $TEMPLATE_MASK $OUTPUT_DIR $OUTPUT_FILE_ROOT ${DWI_1} ${DWI_2} ...  ${DWI_N}

NII2DT_DIR=$1
HOME=$2

shift 2


# Needed because voxbo doesn't know your home directory
# which wouldn't matter except that dcm2nii insists on writing there
export HOME

echo "Running on $HOSTNAME"

cmd="${NII2DT_DIR}/nii2dt.sh $*"

echo $cmd

$cmd


