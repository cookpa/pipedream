
#!/usr/bin/perl -w
#
# Processes of DICOM DWI data and reconstructs diffusion tensors
#

my $usage = qq{
Usage: nii2dt.pl --dwi dwi1.nii.gz dwi2.nii.gz --bvals bvals1 bvasl2 --bvecs bvecs1 bvecs2 --mask mask --outrooot outroot --outdir outdir

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
use Getopt::Long;

my @dwiImages = ();
my @bvals = ();
my @bvecs = ();
my @scheme = ();
my $outputFileRoot = "";
my $outputDir = "";
my $verbose = 0;

my @exts = (".bval", ".bvec", ".nii", ".nii.gz", ".scheme" );

GetOptions ("dwi=s{1,1000}" => \@dwiImages,    # string
	    "bvals=s{1,1000}" => \@bvals, 
	    "bvecs=s{1,1000}" => \@bvecs,
	    "scheme=s{1,1000}" => \@scheme,
	    "outdir=s" => \$outputDir,
	    "outroot=s" => \$outputFileRoot,
	    "verbose"  => \$verbose)   # flag
    or die("Error in command line arguments\n");

if ( $verbose ) {
    print( "DWI:\n @dwiImages \n");
    print( "BVALS:\n @bvals \n");
    print( "BVECS:\n @bvecs \n");
    print( "SCHEME:\n @scheme\n");
    print("OUTROOT: $outputFileRoot \n");
    print("OUTDIR: $outputDir \n");
}

# Set to 1 to delete intermediate files after we're done
# Has no effect if using qsub since files get cleaned up anyhow
my $cleanup=1;

# Get the directories containing programs we need
my ($antsDir, $caminoDir, $tmpDir) = @ENV{'ANTSPATH', 'CAMINOPATH', 'TMPDIR'};

# Process command line args
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


# FIXME - warnings/error related to command line ops
my $numScans = scalar(@dwiImages);
print "\nProcessing " . $numScans . " scans.\n";

if ( scalar(@scheme) == 0) {
    if ( !scalar(@bvals) || !scalar(@bvecs) ) {
	die( "Missing bvecs or bvals, cannot proceed with DT reconstruction");
    }
    if ( scalar(@bvals) != scalar(@bvecs) ) {
	die( "Inconsistant number of bvecs and bvals, cannot proceed with DT reconstruction");
    }
    
    if ( (scalar(@bvals) != scalar(@dwiImages)) &&
	 (scalar(@bvals) != 1) ) {
	die( "Number of bvals files must be same as dwi-images or 1");
    }
    
    if ( (scalar(@bvecs) != scalar(@dwiImages)) &&
	 (scalar(@bvecs) != 1) ) {
	die( "Number of bvecs files must be same as dwi-images or 1");
    }
}
else {
    if ( (scalar(@scheme) != scalar(@dwiImages)) &&
	 (scalar(@scheme) != 1) ) {
	die( "Number of scheme files must be same as dwi-images or 1");
    } 
}
     

# done with args

# ---OUTPUT FILES AND DIRECTORIES---

# Some output is hard coded as ${outputFileRoot}_something

my $outputSchemeFile = "${outputDir}/${outputFileRoot}allscans.scheme";

my $outputDWI_Dir = "${outputDir}/${outputFileRoot}dwi";

my $outputImageListFile = "${outputDWI_Dir}/${outputFileRoot}imagelist.txt";

my $outputBrainMask = "${outputDir}/${outputFileRoot}brainmask.nii.gz";

my $outputAverageDWI = "${outputDir}/${outputFileRoot}averagedwi.nii.gz";

my $outputDWI = "${outputDir}/${outputFileRoot}dwi.nii.gz";

# ---OUTPUT FILES AND DIRECTORIES---



# -bscale 1 produces b values in 2 / mm ^2 on Siemens scanners. Adjust to taste
my $nBFiles = scalar(@bvals);
if ( scalar(@scheme) == 0 ) {
    for (my $i = 0; $i < $nBFiles; $i += 1) {
	my $bname = basename($bvals[$i], @exts);
	my $sname = "${outputDir}/${bname}.scheme";
	push(@scheme, $sname);
	print "$sname\n";
	my $bval = $bvals[$i];
	my $bvec = $bvecs[$i];
	system("${caminoDir}/fsl2scheme -bscale 1 -bvals $bval -bvecs $bvec > $sname");
    }
}

# If using repeats of same scheme 
if ( (scalar(@scheme)==1) && (scalar(@dwiImages) > 1) ) {
    print("Assuming repeats of same acquisition scheme\n");
    for ( my $i=1; $i < scalar(@dwiImages); $i += 1) {
	push(@scheme, $scheme[0]);
    }
}

my $masterScheme = "${outputDir}/${outputFileRoot}master.scheme";
system("cat $scheme[0] | grep -v \"^\$\" > $masterScheme");

if ( scalar(@scheme) > 1 ) {
    for ( my $i = 1; $i < scalar(@scheme); $i += 1 ) {
	system( "cat $scheme[$i] | grep -v \"^\$\" | grep -v \"VERSION\" |  grep -v \"#\" >> $masterScheme");
   }
}
system("cp $dwiImages[0] $outputDWI");
if ( scalar(@dwiImages) > 1 ) {
    print( "Merging acquistions for motion correction \n");
    for ( my $i = 1; $i < scalar(@dwiImages); $i += 1) {
	system("${antsDir}/ImageMath 4 $outputDWI stack $outputDWI $dwiImages[$i]");
    }
}

my $ref = "${outputDir}/${outputFileRoot}ref.nii.gz";
system("${antsDir}/antsMotionCorr -d 3 -a $outputDWI -o $ref");
system("${antsDir}/antsMotionCorr -d 3 -m MI[${outputDir}/${outputFileRoot}ref.nii.gz,${outputDWI}, 1, 32, Regular, 0.05] -u 1 -t Affine[0.2] -i 25 -e 1 -f 1 -s 0 -l 0 -o [${outputDir}/${outputFileRoot}, ${outputDWI}, $ref ]");

# Mask brain - FIXME
#maskBrain($outputAverageDWI, $outputBrainMask, $dwiTemplate, $dwiTemplateMask);

# Now ready to do reconstruction
# Don't pipe because of cluster memory restrictions
print( "Begin DT reconstruction\n");
system("${caminoDir}/image2voxel -4dimage $outputDWI > ${tmpDir}/vo.Bfloat"); 

system("${caminoDir}/wdtfit ${tmpDir}/vo.Bfloat $masterScheme ${tmpDir}/sigmaSq.img -outputdatatype float > ${tmpDir}/dt.Bfloat");

system("cat ${tmpDir}/sigmaSq.img | voxel2image -inputdatatype double -header $ref -outputroot ${outputDir}/${outputFileRoot}sigmaSq");

system("${caminoDir}/dt2nii -header $ref -outputroot ${outputDir}/${outputFileRoot} -inputfile ${tmpDir}/dt.Bfloat -inputdatatype float -outputdatatype float -gzip");

# Add images for QC
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}fa.nii.gz TensorFA ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}md.nii.gz TensorMeanDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}rd.nii.gz TensorRadialDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("$antsDir/ImageMath 3 ${outputDir}/${outputFileRoot}rgb.nii.gz TensorColor ${outputDir}/${outputFileRoot}dt.nii.gz");


# cleanup
if ($cleanup) { 
    `rm -rf $tmpDir`;
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



