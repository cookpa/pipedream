#!/usr/bin/perl -w
#
# Processes of DICOM DWI data and reconstructs diffusion tensors
#

my $usage = qq{
Usage: nii2dt.sh <bvals> <bvecs> <template> <template_mask> <output_dir> <output_file_root> <dwi_1> [dwi_2] ... [dwi_N]


  <bvals> - use specified b-values instead of those defined in the DICOM files

  <bvecs> - use specified b-vectors instead of those defined in the DICOM files

  <template> - template to match to the average DWI image

  <template_mask> - template brain mask to bring back to subject space

  Program can proceed without masks (use NA NA) - but no brain masking will be done in that case.

  <output_dir> - Output directory.

  <output_file_root> - Root of output, eg subject_TP1_dti_ . Prepended onto output files and directories in
    <output_dir>. This should be unique enough to avoid any possible conflict within your data set.

  <dwi_1> - 4D NIFTI image containing DWI data matching the scheme file. Optionally, this may be followed
    by other images containing repeat scans; the combined data will be used to fit the diffusion tensor.


};

use strict;
use FindBin qw($Bin);
use File::Path;
use File::Spec;
use File::Basename;


# Set to 1 to delete intermediate files after we're done
# Has no effect if using qsub since files get cleaned up anyhow
my $cleanup=0;

# Output directory
my $outputDir = "";

# Output file root
my $outputFileRoot = "";

# Get the directories containing programs we need
my ($antsDir, $caminoDir, $tmpDir) = @ENV{'ANTSPATH', 'CAMINOPATH', 'TMPDIR'};

# File names of bvals and bvecs to use if we can't rely on those derived from the data
my $bvals = "";
my $bvecs = "";

# Templates
my $dwiTemplate = "";
my $dwiTemplateMask = "";

my @dwiImages = ();

# Process command line args

if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
else { 
    
    ($bvals, $bvecs, $dwiTemplate, $dwiTemplateMask, $outputDir, $outputFileRoot, @dwiImages) = @ARGV;

}

if ( ! -d $outputDir ) { 
  mkpath($outputDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $outputDir\n\t";
}

# Directory for temporary files that we will optionally clean up when we're done
# Use SGE_TMP_DIR if possible to avoid hammering NFS
if ( !($tmpDir && -d $tmpDir) ) {
    $tmpDir = $outputDir . "/${outputFileRoot}dtiproc";

    mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir\n\t";

    print "Placing working files in directory: $tmpDir\n";
}

# done with args

# ---OUTPUT FILES AND DIRECTORIES---

# Some output is hard coded as ${outputFileRoot}_something

my $outputSchemeFile = "${outputDir}/${outputFileRoot}allscans.scheme";

my $outputDWI_Dir = "${outputDir}/${outputFileRoot}dwi";

my $outputImageListFile = "${outputDWI_Dir}/${outputFileRoot}imagelist.txt";

my $outputBrainMask = "${outputDir}/${outputFileRoot}brainmask.nii.gz";

my $outputAverageDWI = "${outputDir}/${outputFileRoot}averagedwi.nii.gz";

# ---OUTPUT FILES AND DIRECTORIES---


print "\nProcessing " . scalar(@dwiImages) . " scans.\n";


my $numScans = scalar(@dwiImages);

print "Using bvecs $bvecs\n";
print "Using bvals $bvals\n";

if ( ! (-e $bvecs && -e $bvals) ) {
    die "Missing bvec or bval, cannot proceed with DT reconstruction";
} 

# -bscale 1 produces b values in 2 / mm ^2 on Siemens scanners. Adjust to taste
system("${caminoDir}/fsl2scheme -bscale 1 -bvals $bvals -bvecs $bvecs -numscans $numScans -interleave > $outputSchemeFile");


for (my $counter = 0; $counter < $numScans; $counter++) {

    my $scanCounter = formatScanCounter($counter + 1);

    system("${caminoDir}/split4dnii -inputfile $dwiImages[$counter] -outputroot ${tmpDir}/${outputFileRoot}S${scanCounter}_");
}



# Use bvals to determine indices of a reference b=0 volume and other b=0 volumes
# We use bvals and not the scheme file, because the scheme file includes repeats
open(FILE, "<$bvals") or die $!;


# Array contains b-values for each measurement
my @bvalues = split('\s+', <FILE>);

close(FILE);

# Complete path to all images with b=0
my @zeroImages= (); 

# Complete path to all images with b > 0
my @dwImages= (); 

# Image list contains all corrected image file names. 
# This file is for image2voxel and contains no path information, just file names
my @imageList = ();

# File name to which we write this
my $imageListFile = "${tmpDir}/imagelist.txt";

# Loop over b-values. If b=0, add the corresponding 3D volume from all scans to
# the list of b=0 scans, else add to list of DW scans
foreach my $i (0 .. $#bvalues) {
    foreach my $s (0 .. ($numScans - 1)) {
	# no path information because we want the image list to remain valid after we move the images
	my $imageFilename = ${outputFileRoot} . "S" . formatScanCounter($s + 1) . "_" . sprintf("%04d", ($i+1)) . ".nii.gz";

	my $pathToImage = "${tmpDir}/$imageFilename";
	
	if ($bvalues[$i] == 0) {
	    push(@zeroImages, $pathToImage);
	}
	else {
	    push(@dwImages, $pathToImage);
	}

	my $correctedFileName = $imageFilename;

	# Assuming name of corrected file here, better to get it from function call
	$correctedFileName =~ s/\.nii\.gz$/_corrected\.nii\.gz/;

	push(@imageList, $correctedFileName);
    }
} 

# Write image list to disk. This is a list of corrected 3D volumes
# in the order in which they appear in the scheme file
open(FILE, ">$imageListFile") or die $!;

foreach my $imageListEntry (@imageList) {
    print FILE "$imageListEntry\n";
}

close FILE;


print "\nFound " . scalar(@zeroImages) . " b=0 scans\n";

# In theory there could be no b=0 images, but we don't deal with that for now
if (scalar(@zeroImages) == 0) { 
    print "\nDid not find any b=0 images. Unable to continue\n";
    exit 1;
}

# $referenceB0 contains an absolute path
my $referenceB0 = shift(@zeroImages);

print "\nUsing $referenceB0 as reference volume\n";

# Write null transform and feed reference image to ANTS
# This ensures a consistent header / data type for all output images 
open (FILE, ">${tmpDir}/nullTransform.txt") or die $!;

my $nullTrans = qq/
#Insight Transform File V1.0
# Transform 0
Transform: MatrixOffsetTransformBase_double_3_3
Parameters: 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0
FixedParameters: 0.0 0.0 0.0
/;

print FILE $nullTrans;

close FILE;

my $referenceB0Correct = $referenceB0;

$referenceB0Correct =~ s/\.nii\.gz$/_corrected\.nii\.gz/;

`$antsDir/WarpImageMultiTransform 3 $referenceB0 $referenceB0Correct -R $referenceB0 ${tmpDir}/nullTransform.txt`;

# Corrected b=0 images
my @zeroImagesCorrect;

my $averageB0 = "${tmpDir}/b0_mean.nii.gz";

if (scalar(@zeroImages) == 0) {

    # just one b=0 image.
    `cp $referenceB0Correct $averageB0`;

    unshift(@zeroImagesCorrect, $referenceB0Correct);
}
else {

    # Register all b=0 volumes to reference
    @zeroImagesCorrect = motionCorrect($referenceB0, @zeroImages);

    unshift(@zeroImagesCorrect, $referenceB0Correct);

    # Average registered b=0 volumes
    averageImages($averageB0, @zeroImagesCorrect);
    
}

print "b=0 images corrected. Correcting " . scalar(@dwImages) . " DW images\n";

# Register all b > 0 volumes to b0_mean
my @dwiImagesCorrect = motionCorrect($averageB0, @dwImages);

# Make output directory for DWI images (and the rest if necessary)
system("mkdir -p ${outputDWI_Dir}");

# Make average DWI image
averageImages($outputAverageDWI, @dwiImagesCorrect);

# Mask brain - FIXME
maskBrain($outputAverageDWI, $outputBrainMask, $dwiTemplate, $dwiTemplateMask);

# Now ready to do reconstruction
# Don't pipe because of cluster memory restrictions

system("${caminoDir}/image2voxel -imageprefix ${tmpDir}/ -imagelist $imageListFile > ${tmpDir}/vo.Bfloat"); 

system("${caminoDir}/wdtfit ${tmpDir}/vo.Bfloat $outputSchemeFile ${tmpDir}/sigmaSq.img -outputdatatype float -bgmask $outputBrainMask > ${tmpDir}/dt.Bfloat");

system("cat ${tmpDir}/sigmaSq.img | voxel2image -inputdatatype double -header $referenceB0Correct -outputroot ${outputDir}/${outputFileRoot}sigmaSq.nii.gz");

system("${caminoDir}/dt2nii -header $referenceB0Correct -outputroot ${outputDir}/${outputFileRoot} -inputfile ${tmpDir}/dt.Bfloat -inputdatatype float -outputdatatype float -gzip");

system("mv ${tmpDir}/*correctedAffine.txt ${outputDWI_Dir}");

system("mv $imageListFile $outputImageListFile");

`mv $outputSchemeFile ${outputDir}/`;

# image list entries contain no path information
foreach my $imageListEntry (@imageList) {
    `mv ${tmpDir}/$imageListEntry $outputDWI_Dir`;
}

# Add images for QC
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}fa.nii.gz TensorFA ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}md.nii.gz TensorMeanDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}rgb.nii.gz TensorColor ${outputDir}/${outputFileRoot}dt.nii.gz");


# cleanup
if ($cleanup) { 
    `rm -rf $tmpDir`;
}



# formatScanCounter($counter)
#
# Formats the scan counter such that qq("S_" formatScanCounter($counter)) gives the root
# of the DWI images that have been produced by this script.
sub formatScanCounter {
    
    my $scanCounter = shift; # first argument

    return sprintf("%03d", $scanCounter);
}


# Normalizes all images to the reference volume
#
# @corrected = motionCorrect($fixedImage, @movingImages);
#
# Returns array of corrected images. If the moving image is ${movingRoot}.nii.[gz], then
# the corrected image is ${moving}_corrected.nii.gz. Eg S001_0001.nii.gz -> S001_0001_corrected.nii.gz
# 
# Affine transformations are written to ${movingRoot}_correctedAffine.txt
#
sub motionCorrect {


    my ($fixed, @moving) = @_;

    # corrected image names
    my @corrected = ();

    foreach my $image (@moving) {

	$image =~ m/(.*)(\.nii)(\.gz)?$/;

	my $imageRoot = $1;

	my $ext = "nii.gz";

	my $out="${imageRoot}_corrected.$ext";

        my $DEFORMABLEITERATIONS=0;    # for affine only 
        #my $DEFORMABLEITERATIONS="1x0x0";  # for a little fun with deformation 

	my $cmd = "$antsDir/ANTS 3 -m MI[${fixed},${image},1,16] -t SyN[1] -r Gauss[3,1] -o $out -i $DEFORMABLEITERATIONS";

	print "\n  $cmd \n";

	system($cmd);
 
        system("$antsDir/WarpImageMultiTransform 3 $image $out -R $fixed  ${imageRoot}_correctedAffine.txt"); 

	print "Corrected image $out written\n";

	push(@corrected, $out);

    }

    return @corrected;

}


# Averages images
#
# averageImages($average, @imagesToAverage) 
#
# Arguments should both include full path to images
#
sub averageImages {

    my ($average, @imagesToAverage) = @_;

    # use ants
    system("${antsDir}/AverageImages 3 $average 0 @imagesToAverage");

} 



# Computes brain mask from the average DWI image 
#
#
# maskBrain($dwiMean, $maskFile, $template, $templateMask) 
#
#
sub maskBrain {

    my ($dwiMean, $maskFile, $template, $templateMask) = @_;
      

    if ( -f $template) {

	my $inputTrunc = "${tmpDir}/averagedwi_truncated.nii.gz";
	
	system("${antsDir}/ImageMath 3 $inputTrunc TruncateImageIntensity $dwiMean 0.0 0.99");

        # Use CC for affine metric type - better behaved
	system("${antsDir}/ANTS 3 -m MI[${template},${inputTrunc},1,32] -o ${tmpDir}/subj2templateAffine.nii.gz -i 0 --number-of-affine-iterations 10000x10000 --affine-metric-type CC --use-Histogram-Matching true");
	
        # Dilate template mask to include boundary of brain - going to use this to mask registration
	my $templateMaskDilated = "${tmpDir}/templateMaskDilated.nii.gz";

	system("${antsDir}/ImageMath 3 $templateMaskDilated MD $templateMask 2");

	# Now use MI in the masked space to refine the affine, but only at full resolution - avoids weird instability
	system("${antsDir}/ANTS 3 -m CC[${template},${inputTrunc},1,3] -o ${tmpDir}/averagedwi2template.nii.gz -i 40x40 -t Syn[0.2] -r Gauss[3,0] --continue-affine true --initial-affine ${tmpDir}/subj2templateAffineAffine.txt --number-of-affine-iterations 10000 --affine-metric-type MI -x $templateMaskDilated");

	# Warp the template mask to the subject space
	system("${antsDir}/WarpImageMultiTransform 3 $templateMask $maskFile -R ${dwiMean} -i ${tmpDir}/averagedwi2templateAffine.txt ${tmpDir}/averagedwi2templateInverseWarp.nii.gz");

	system("${antsDir}/ThresholdImage 3 $maskFile $maskFile 0.5 Inf");

	# N4
	my $dwiMeanN4 = "${tmpDir}/averagedwi_n4.nii.gz";

	my $ITS = 20;

	system("${antsDir}/N4BiasFieldCorrection -d 3 -h 0 -i $inputTrunc -o $dwiMeanN4 -s 2 -b [200] -c [${ITS}x${ITS}x${ITS},0.00001] -x $maskFile");


	system("${antsDir}/ANTS 3 -m CC[${template},${dwiMeanN4},1,3] -o ${tmpDir}/averagedwi2template.nii.gz -i 40x40 -t Syn[0.2] -r Gauss[3,0] --use-Histogram-Matching  --continue-affine true --initial-affine ${tmpDir}/averagedwi2templateAffine.txt --number-of-affine-iterations 10000 --affine-metric-type MI -x $templateMaskDilated");


	system("${antsDir}/WarpImageMultiTransform 3 $templateMask $maskFile -R ${dwiMean} -i ${tmpDir}/averagedwi2templateAffine.txt ${tmpDir}/averagedwi2templateInverseWarp.nii.gz");

        # Threshold and close holes

	system("${antsDir}/ThresholdImage 3 $maskFile $maskFile 0.5 Inf");
	system("${antsDir}/ImageMath 3 $maskFile PadImage $maskFile 10");
	system("${antsDir}/ImageMath 3 $maskFile MD $maskFile 2");
	system("${antsDir}/ImageMath 3 $maskFile ME $maskFile 2");
	system("${antsDir}/ImageMath 3 $maskFile PadImage $maskFile -10");


    }
    else {
	
	# No template. Could do something with Atropos here?

	system("${antsDir}/ThresholdImage 3 $dwiMean $maskFile 0 Inf");
	
    }
    
    return $maskFile;

}



