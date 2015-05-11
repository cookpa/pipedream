
#!/usr/bin/perl -w
#
# Processes of DICOM DWI data and reconstructs diffusion tensors
#

my $usage = qq{
Usage: nii2dt --dwi dwi1.nii.gz dwi2.nii.gz --bvals bvals1 bvals2 --bvecs bvecs1 bvecs2 --correction-target [b0 | dwi | mean]  --outroot outroot --outdir outdir

  <outdir> - Output directory.

  <outroot> - Root of output, eg subject_TP1_dti_ . Prepended onto output files and directories in
    <outdir>. This should be unique enough to avoid any possible conflict within your data set.

  <dwi_1> - 4D NIFTI image containing DWI data. Optionally, this may be followed by other images and bvals / bvecs 
  containing repeat scans; the combined data will be used to fit the diffusion tensor.

  Distortion / motion correction is to the average b=0 image by default; set --correction-target dwi to use
  the median DWI image or mean to use the mean of all data (the old default).

};

use strict;
use FindBin qw($Bin);
use File::Path;
use File::Spec;
use File::Basename;
use Getopt::Long;

my @dwiImages = ();
my @bvals = ();
my @bvecs = ();
my $outputFileRoot = "";
my $outputDir = "";
my $verbose = 0;
my $distCorrTargetImageType = "b0";

if ($#ARGV < 0) {
    print $usage;
    exit 1;
}

my @exts = (".bval", ".bvec", ".nii", ".nii.gz", ".scheme" );

GetOptions ("dwi=s{1,1000}" => \@dwiImages,    # string
	    "bvals=s{1,1000}" => \@bvals,
	    "bvecs=s{1,1000}" => \@bvecs,
	    "outdir=s" => \$outputDir,
	    "outroot=s" => \$outputFileRoot,
	    "verbose"  => \$verbose,
	    "correction-target=s" => \$distCorrTargetImageType )   # flag
    or die("Error in command line arguments\n");

# Convert string options to lower case 
$distCorrTargetImageType = lc($distCorrTargetImageType);

if ( $verbose ) {
    print( "DWI:\n @dwiImages \n");
    print( "BVALS:\n @bvals \n");
    print( "BVECS:\n @bvecs \n");
    print("OUTROOT: $outputFileRoot \n");
    print("OUTDIR: $outputDir \n");
}

# Set to 1 to delete intermediate files after we're done
# Has no effect if using qsub since files get cleaned up anyhow
my $cleanup=1;

# Get the directories containing programs we need
my ($antsDir, $caminoDir, $sysTmpDir) = @ENV{'ANTSPATH', 'CAMINOPATH', 'TMPDIR'};

# Process command line args
if ( ! -d $outputDir ) {
  mkpath($outputDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $outputDir\n\t";
}

# Directory for temporary files that is deleted later if $cleanup
my $tmpDir = "";

my $tmpDirBaseName = "${outputFileRoot}dtiproc";

if ( !($sysTmpDir && -d $sysTmpDir) ) {
    $tmpDir = $outputDir . "/${tmpDirBaseName}";
}
else {
    # Have system tmp dir
    $tmpDir = $sysTmpDir . "/${tmpDirBaseName}";
}

mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir\n\t";


my $numScans = scalar(@dwiImages);

print "\nProcessing " . $numScans . " scans.\n";

if ( !scalar(@bvals) || !scalar(@bvecs) ) {
    die( "Missing bvecs or bvals, cannot proceed with DT reconstruction");
}
if ( scalar(@bvals) != scalar(@bvecs) ) {
    die( "Inconsistant number of bvecs and bvals, cannot proceed with DT reconstruction");
}
if ( scalar(@bvals) != $numScans ) {
    die( "Number of bvals files must be same as the number of DWI images");
}
if ( scalar(@bvecs) != $numScans ) { 
    die( "Number of bvecs files must be same as DWI images");
}


# done with args

# ---OUTPUT FILES AND DIRECTORIES---

# Some output is hard coded as ${outputFileRoot}_something

my $outputDWI_Dir = "${outputDir}/${outputFileRoot}dwi";

my $outputImageListFile = "${outputDWI_Dir}/${outputFileRoot}imagelist.txt";

my $outputAverageB0 = "${outputDir}/${outputFileRoot}averageB0.nii.gz";

my $outputAverageDWI = "${outputDir}/${outputFileRoot}averageDWI.nii.gz";

my $outputDWI = "${outputDir}/${outputFileRoot}dwi.nii.gz";

# ---OUTPUT FILES AND DIRECTORIES---

my $bvalMaster = "${tmpDir}/${outputFileRoot}master.bval";
my $bvecMaster = "${tmpDir}/${outputFileRoot}master.bvec";

if ( $numScans > 1 ) {
    my $bvalFileNames = join(" ", @bvals);

    system("paste -d \" \" $bvalFileNames > $bvalMaster");

    # Make sure there is no double spacing - it breaks space delimited ITK readers
    open(my $fh, "<", "$bvalMaster") or die "Cant open $bvalMaster\n";
 
    local $/ = undef;
    
    my $bvalString = <$fh>;
    
    close($fh);
    
    $bvalString =~ s/[ ]{2,}/ /g;
    
    open($fh, ">", "$bvalMaster") or die "Cant open $bvalMaster\n";

    print $fh $bvalString;

    close($fh);

}
else {
    system("cp $bvals[0] $bvalMaster");
}
if ( $numScans > 1 ) {

    my $bvecFileNames = join(" ", @bvecs);

    system("paste -d \" \" $bvecFileNames > $bvecMaster");

    # Make sure there is no double spacing - it breaks space delimited ITK readers
    open(my $fh, "<", "$bvecMaster") or die "Cant open $bvecMaster\n";
 
    local $/ = undef;
    
    my $bvecString = <$fh>;
    
    close($fh);
    
    $bvecString =~ s/[ ]{2,}/ /g;
    
    open($fh, ">", "$bvecMaster") or die "Cant open $bvecMaster\n";

    print $fh $bvecString;

    close($fh);
}
else {
    system("cp $bvecs[0] $bvecMaster");
}


my @scheme = ();

# Make Camino scheme version from supplied bvals / bvecs

my $masterScheme = "${tmpDir}/${outputFileRoot}master.scheme";

system("${caminoDir}/fsl2scheme -bscale 1 -bvals $bvalMaster -bvecs $bvecMaster > $masterScheme");
 

my $uncorrectedDWI = "${tmpDir}/${outputFileRoot}dwi.nii.gz";

system("cp $dwiImages[0] $uncorrectedDWI");
if ( scalar(@dwiImages) > 1 ) {
    print( "Merging acquistions for motion correction \n");
    for ( my $i = 1; $i < scalar(@dwiImages); $i += 1) {
	system("${antsDir}/ImageMath 4 $uncorrectedDWI stack $uncorrectedDWI $dwiImages[$i]");
    }
}

my $ref = "${tmpDir}/${outputFileRoot}ref.nii.gz";

if ($distCorrTargetImageType eq "b0") {
    print " Using average b=0 for distortion / motion correction \n";

    system("${caminoDir}/averagedwi -inputfile $uncorrectedDWI -outputfile $ref -minbval 0 -maxbval 0 -schemefile $masterScheme");
}
elsif ($distCorrTargetImageType eq "dwi") {
    print " Using median DWI for distortion / motion correction \n";

    system("${caminoDir}/averagedwi -inputfile $uncorrectedDWI -outputfile $ref -minbval 500 -maxbval 1500 -schemefile $masterScheme -median");
}
elsif ($distCorrTargetImageType eq "mean") {
    print " Using mean of all measurements for distortion / motion correction \n";

    system("${caminoDir}/averagedwi -inputfile $uncorrectedDWI -outputfile $ref -schemefile $masterScheme");
}
else {
    die "Unrecognized target image type $distCorrTargetImageType, valid choices are 'b0' or 'dwi'";
}

system("${antsDir}/antsMotionCorr -d 3 -m MI[${ref},${uncorrectedDWI}, 1, 32, Regular, 0.125] -u 1 -t Affine[0.2] -i 25 -e 1 -f 1 -s 0 -o [${outputDir}/${outputFileRoot}, ${outputDWI}]");

# Compute corrected average DWI and B0
system("${caminoDir}/averagedwi -inputfile $outputDWI -outputfile ${outputDir}/${outputFileRoot}averageB0.nii.gz -minbval 0 -maxbval 0 -schemefile $masterScheme");

system("${caminoDir}/averagedwi -inputfile $outputDWI -outputfile ${outputDir}/${outputFileRoot}averageDWI.nii.gz -minbval 500 -maxbval 1500 -schemefile $masterScheme");

system("${caminoDir}/averagedwi -inputfile $outputDWI -outputfile ${outputDir}/${outputFileRoot}medianDWI.nii.gz -minbval 500 -maxbval 1500 -schemefile $masterScheme -median");


# Correct directions via motion correction parameters
print( "Correcting gradient directions\n" );
my $correctedScheme = "${outputDir}/${outputFileRoot}corrected.scheme";
my $bvecCorrected = "${outputDir}/${outputFileRoot}corrected.bvec";

# B-values don't change but call them the same thing 
system("cp $bvalMaster ${outputDir}/${outputFileRoot}corrected.bval");

my $cmd = "${antsDir}/antsMotionCorrDiffusionDirection --bvec $bvecMaster --output $bvecCorrected --moco ${outputDir}/${outputFileRoot}MOCOparams.csv --physical ${ref}";

system("$cmd");

system("${caminoDir}/fsl2scheme -bscale 1 -bvals $bvalMaster -bvecs $bvecCorrected > $correctedScheme");

# For debugging and possible visualization of correction, output uncorrected scheme also
system("cp $masterScheme ${outputDir}/${outputFileRoot}uncorrected.scheme");


# Now ready to do reconstruction
# Don't pipe because of cluster memory restrictions
print( "Begin DT reconstruction\n");
system("${caminoDir}/image2voxel -4dimage $outputDWI > ${tmpDir}/vo.Bfloat");

print("wdtfit\n");

# Note the sigmaSq image is always written as double, the tensor type is controlled by -outputdatatype
system("${caminoDir}/wdtfit ${tmpDir}/vo.Bfloat $correctedScheme ${tmpDir}/sigmaSq.img -outputdatatype float > ${tmpDir}/dt.Bfloat");

print("sigma img\n");
system("cat ${tmpDir}/sigmaSq.img | ${caminoDir}/voxel2image -header $ref -outputvector -outputroot ${outputDir}/${outputFileRoot}sigmaSq");

print("dt2nii\n");
system("${caminoDir}/dt2nii -header $ref -outputroot ${outputDir}/${outputFileRoot} -inputfile ${tmpDir}/dt.Bfloat -inputdatatype float -outputdatatype float -gzip");

# Add images for QC
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}fa.nii.gz TensorFA ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}md.nii.gz TensorMeanDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}rd.nii.gz TensorRadialDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}rgb.nii.gz TensorColor ${outputDir}/${outputFileRoot}dt.nii.gz");


# cleanup
if ($cleanup) {

    # rm -rf is scary, so check to be sure
   
    if ($tmpDir =~ m/${tmpDirBaseName}$\/?/) {
	system("rm -rf $tmpDir");
    }
    else {
	die "$tmpDir - temp directory name unrecognized - not safe to delete, processing may be incomplete"
    }

}
