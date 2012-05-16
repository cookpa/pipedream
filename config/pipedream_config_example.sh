#
# This is an example config file - copy this to /path/to/pipedream/config/pipedream_config.sh
# and edit as needed
#

# === SOFTWARE DEPENDENCIES ===
#
# PipeDream depends on various open source software
#
# Not all dependencies are required at all stages of processing. 
#
# For more details on how to obtain / build these programs, see the PipeDream
# documentation.

# Paths to software should end in a slash eg ANTSPATH=/path/to/ants/

# ====== DICOM TOOLS =======
#
# dcm2nii is part of mricron by Chris Rorden
# http://www.nitrc.org/projects/mricron
#
export DCM2NIIPATH="/home/pcook/grosspeople/research/mricron/"
#
# GDCM (Grassroots DiCoM) is a C++ library for DICOM medical files
# http://sourceforge.net/projects/gdcm/
#
export GDCMPATH="/home/pcook/grosspeople/research/gdcm/bin/"
#
# Path to XML files needed by GDCM
export GDCM_RESOURCES_PATH="/home/pcook/grosspeople/research/gdcm/Source/InformationObjectDefinition/"


# ====== IMAGE PROCESSING TOOLS ======
#
# ANTS contains advanced tools for image registration and segmentation. It's used in almost 
# every part of PipeDream
#
# http://www.picsl.upenn.edu/ANTS/
#
export ANTSPATH="/home/pcook/grosspeople/research/ants_r1098/"
#
# Camino is a diffusion imaging toolkit
# 
# http://camino.org.uk
#
export CAMINOPATH="/home/pcook/grosspeople/research/camino/bin/"
#
# Java is required by Camino
export JAVAPATH="/usr/java/latest/bin/"
#
# Control maximum memory usage by Camino, in Mb
export CAMINO_HEAP_SIZE=1100



#
# === GENERAL CONFIGURATION OPTIONS ===
#
# Maximum number of threads used by ITK programs (ie, ANTS).
# To avoid overloading cluster machines with multiple threads, set this to 1
# 
# Increasing this number will let ITK use more threads, which can make
# processing much faster
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1


# === PARALLEL PROCESSING OPTIONS ===
#
# The qsub commmand that will be invoked by pipedream. Include path information and
# options such as -q that may be necessary. Beware that some options, like -o or -S,
# may be set at run time by pipedream programs. Some recommended options:
#
# -q   Restrict submission to a particular queue, useful for limiting the number of
#      concurrent jobs
#
# -p   Set job priority, another way to avoid being a cluster hog
#
# -P   Set project for job, used on clusters where CPU time is controlled by project
#
# -v   Pass environment variable to the job.
#
# -V   Pass current environment (all variables) to the job. You should keep this to 
#      ensure that variables defined in this file get sent to the job.
#
# See the man page for qsub for more detail.
#
PIPEDREAMQSUB="qsub -pe serial 2 -V "
#
#
# The Voxbo vbbatch commmand that will be invoked by pipedream. Include path information 
# and options that may be necessary.
#
PIPEDREAMVBBATCH="vbbatch"


return 0
