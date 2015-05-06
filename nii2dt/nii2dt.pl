# Called from bash wrapper to initialize library path
#
#
# Processes raw Nifti DWI data and reconstructs diffusion tensors
#
#
my $usage = qq{
Usage: nii2dt --dwi dwi.nii.gz --bvals bvals --bvecs bvecs --output-file-root file_root --output-dir out_dir [options]

  Required args

  --dwi dwi.nii.gz
    4D NIFTI image containing DWI data.

  --bvals bvals
    b-values in FSL format.

  --bvecs bvecs
    b-vectors in FSL format.

    The b-values and b-vectors should match the measurements in dwi.nii.gz.

  --output-file-root file_root
    Root of output, eg subject_MRIDate_dti_ . Prepended onto output files <out_dir>. 

  --output-dir out_dir
    Directory for output.


  To concatenate separate DWI series into a single output, pass multiple arguments to --dwi and if appropriate --bvals / --bvecs.

  For example:

    --dwi dwi1.nii.gz dwi2.nii.gz dwi3.nii.gz  --bvals dwi_bval  --bvecs dwi_bvec

  This assumes three repeats of the same sequence, each described using the same bvals / bvecs. If the imaging scheme is not 
  identical across series, the schemes can be passed explicitly in order, eg:

    --dwi dwi1.nii.gz dwi2.nii.gz  --bvals dwi_bval1 dwi_bval2  --bvecs dwi_bvec1 dwi_bvec2


  Optional args and parameters:


  --motion-correction-transform affine | rigid | none 
    The default transform for motion / distortion correction is affine. Optionally this may be set to "rigid" or "none".

  --unweighted-b-value 0 
    The maximum b-value to be treated as unweighted. Some acquisition schemes acquire a small b-value rather than 0, 
    so it may be necessary to tell the script to collect unweighted images in a non-zero range. For example, passing 5 here
    will treat anything with a b-value between 0 and 5 as if it were 0. 

  --verbose 
    Enables verbose output.

};

use strict;

use FindBin qw($Bin);
use File::Path;
use File::Spec;
use File::Basename;
use Getopt::Long;

use PipeDream::Dependencies;

my @dwiImages = ();
my @bvals = ();
my @bvecs = ();
my $outputFileRoot = "";
my $outputDir = "";
my $verbose = 0;
my $mocoTransform = "affine";

my $unweightedB_Val = 0;

my @exts = (".bval", ".bvec", ".nii", ".nii.gz");

if ($#ARGV < 0) {
    print $usage;
    exit 1;
}

# Check dependencies
( haveCamino() && haveANTs() ) or die "\nMissing required dependencies, check PATH";


# Process command line args

GetOptions ("dwi=s{1,1000}" => \@dwiImages,    # string
	    "bvals=s{1,1000}" => \@bvals,
	    "bvecs=s{1,1000}" => \@bvecs,
	    "output-dir=s" => \$outputDir,
	    "output-file-root=s" => \$outputFileRoot,
	    "verbose"  => \$verbose, # flag
	    "motion-correction-transform=s" => \$mocoTransform,
	    "unweighted-b-value=f" => \$unweightedB_Val);
    or die("Error in command line arguments\n");

if ( $verbose ) {
    print( "DWI:\n @dwiImages \n");
    print( "BVALS:\n @bvals \n");
    print( "BVECS:\n @bvecs \n");
    print("OUTROOT: $outputFileRoot \n");
    print("OUTDIR: $outputDir \n");
}


# These aren't options and hopefully will work; even multi-shell data should have enough data in this range to 
# make for a useful average DWI image
my $minB_ForAverageDWI = 600;
my $maxB_ForAverageDWI = 1600;


my $numScans = scalar(@dwiImages);
print "\nProcessing " . $numScans . " scans.\n";

# Check args
if ( !scalar(@bvals) || !scalar(@bvecs) ) {
    die( "Missing bvecs or bvals, cannot proceed with DT reconstruction");
}

if ( scalar(@bvals) != scalar(@bvecs) ) {
    die( "Inconsistant number of bvec and bval files, cannot proceed with DT reconstruction");
}

if ( (scalar(@bvals) != $numScans) &&
     (scalar(@bvals) != 1) ) {
    die( "Number of bval files must be 1 or equal to the number of dwi volumes ($numScans).");
}

if ( (scalar(@bvecs) != $numScans) &&
     (scalar(@bvecs) != 1) ) {
    die( "Number of bvec files must be 1 or equal to the number of dwi volumes ($numScans).");
}

if ( !($mocoTransform =~ m/^affine|rigid|none$/i) ) {
    die("Unrecognized motion correction transform $mocoTransform");
}

if ( ! -d $outputDir ) {
  mkpath($outputDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $outputDir";
}

# done with args

# Directory for temporary files that we will optionally clean up when we're done
# Use SGE TMPDIR if possible
if ( !($tmpDir && -d $tmpDir) ) {
    $tmpDir = $outputDir . "/${outputFileRoot}dtiproc";
}
else {
    # Make a tmp dir within $TMPDIR - then we can delete this safely without messing up other processes
    $tmpDir = "$tmpDir/${outputFileRoot}dtiproc";
}

mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir";

if ($verbose) {
    print "Placing working files in directory: $tmpDir\n";
}

# Set to 1 to delete intermediate files after we're done
# Has no effect if using qsub since files get cleaned up anyhow
my $cleanup=1;





# ---OUTPUT FILES AND DIRECTORIES---

# Some output is hard coded as ${outputFileRoot}_something

my $outputAverageDWI = "${outputDir}/${outputFileRoot}averageDWI.nii.gz";

my $outputAverageB0 = "${outputDir}/${outputFileRoot}averageB0.nii.gz";

my $outputDWI = "${outputDir}/${outputFileRoot}dwi.nii.gz";

# ---OUTPUT FILES AND DIRECTORIES---

# Combined, uncorrected bvals and bvecs
my $combinedSchemeFileRoot="${outputDir}/${outputFileRoot}combined";

createCombinedScheme($combinedSchemeFileRoot, $numScans, \@bvals, \@bvecs);

# As created by the above call to createCombinedScheme
my $bvalMaster = "${combinedSchemeFileRoot}.bval";
my $bvecMaster = "${combinedSchemeFileRoot}.bvec";
my $schemeMaster = "${combinedSchemeFileRoot}.scheme";

my $dwiMaster = "${tmpDir}/${outputFileRoot}dwiUncorrected.nii.gz";

system("cp $dwiImages[0] $dwiMaster");

if ( scalar(@dwiImages) > 1 ) {
    print( "Merging acquistions for motion correction \n");
    for ( my $i = 1; $i < scalar(@dwiImages); $i += 1) {
	system("ImageMath 4 $dwiMaster stack $dwiMaster $dwiImages[$i]");
    }
}

runDistCorr($dwiMaster, $schemeMaster, $distcorrRefImageType, $distcorrTransform); 

# Now ready to do reconstruction
# Don't pipe because of cluster memory restrictions
print( "Begin DT reconstruction\n");
system("${caminoDir}/image2voxel -4dimage $outputDWI > ${tmpDir}/vo.Bfloat");

print("wdtfit\n");
system("${caminoDir}/wdtfit ${tmpDir}/vo.Bfloat $correctedScheme ${tmpDir}/sigmaSq.img -outputdatatype float > ${tmpDir}/dt.Bfloat");

print("sigma img\n");
system("cat ${tmpDir}/sigmaSq.img | voxel2image -inputdatatype float -header $ref -outputroot ${outputDir}/${outputFileRoot}sigmaSq");

print("dt2nii\n");
system("${caminoDir}/dt2nii -header $ref -outputroot ${outputDir}/${outputFileRoot} -inputfile ${tmpDir}/dt.Bfloat -inputdatatype float -outputdatatype float -gzip");

# Add images for QC
system("ImageMath 3 ${outputDir}/${outputFileRoot}fa.nii.gz TensorFA ${outputDir}/${outputFileRoot}dt.nii.gz");
system("ImageMath 3 ${outputDir}/${outputFileRoot}md.nii.gz TensorMeanDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("ImageMath 3 ${outputDir}/${outputFileRoot}rd.nii.gz TensorRadialDiffusion ${outputDir}/${outputFileRoot}dt.nii.gz");
system("ImageMath 3 ${outputDir}/${outputFileRoot}rgb.nii.gz TensorColor ${outputDir}/${outputFileRoot}dt.nii.gz");


# cleanup
if ($cleanup) {
    `rm -rf $tmpDir`;
}



# createCombinedScheme($combinedSchemeFileRoot, $numScans, \@bvals, \@bvecs)
#
# Writes ${combinedSchemeFileRoot}.[scheme, bval, bvec]
#
# If $numScans > 1, then repeat $bval[0] and $bvec[0] for all schemes
#
sub createCombinedScheme {
    
    my ($fileRoot, $numScans, $bvalRef, $bvecRef) = @_;

    my @bvalFiles = @${bvalRef};
    my @bvecFiles = @${bvecRef};

    if ( scalar(@bvalFiles) == 1 && $numScans > 1) {
	
    }
    if ( scalar(@bvecFiles) == 1 && $numScans > 1) {
	
    }

    # At this point, should have scalar(@bvalFiles) == scalar(@bvecFiles) == $numScans)

    if (  (scalar(@bvecFiles) != $numScans) || (scalar(@bvalFiles) != $numScans) ) {
	die "Mismatch between bvals, bvecs, and number of scans";
    }

    # Master list of values
    my @bvals = ();

    # Stored in FSL format for ease of writing
    my @bvecs = ();


    # Read bvalues and bvectors in official FSL format - more readable transpose format is rumored to work
    # but not documented as of FSL 5

    my $bvalCounter = 0;
    my $bvecCounter = 0;

    for (my $i = 0; $i < $numScans; $i++) {
	
	open(my $fh, "<$bvalFiles[$i]");
	
	my $line = <$fh>;
	
	my @tokens = split("\s+", trim($line));

	# Number of measurements in this series
	my $numMeas = scalar(@tokens);
	
	foreach my $bValue (@tokens) {
	    $bvals[$bvalCounter++] = $bValue;
	}
	
	close($fh);
	
	open($fh, "<$bvecFiles[$i]");
	
	for (my $n = 0; $n < 3; $n++) {
	    my $line = <$fh>;
	    
	    @tokens = split("\s+", trim($line));

	    if ( scalar(@tokens) != $numMeas ) {
		die " Expected $numMeas b-vectors but got " . scalar(@tokens);
	    }

	    for (my $v = 0; $v < $numMeas; $v++) {
		$bvecs[$n][$bvecCounter + $v] = $tokens[$v];
	    }
	}

	close($fh);

	$bvecCounter += $numMeas;
    }
    

    # Now write them out in FSL format

    open(my $fh, ">${fileRoot}.bval");

    print $fh join(" ", @bvals);

    close($fh);

    
    # Write Camino scheme

}


#
# runDistCorr($dwiMaster, $schemeMaster, $distCorrRefImageType, $distCorrTransform)
#
# $dwiMaster - uncorrected DWI data
# $schemeMaster - uncorrected scheme file
# $distCorrRefImageType - "meanB0" or "meanDWI"
# $distCorrTransform - "affine", "rigid", "none". 
#
# Makes use of script-level variables:
#
# $tmpDir
# $unweightedB_Val
# $outputDir
# $outputfileRoot
# 
sub runDistCorr {


    my ($dwiMaster, $schemeMaster, $outputRoot, $distCorrRefImageType, $distcorrTransform, $its) = @_;
    
    my $distCorrTargetImage;

    # Make initial average b0 / average DWI images
    system("averagedwi -schemefile $schemeMaster -minbval 0 -maxbval $unweightedB_Val -inputfile $dwiMaster -outputfile ${tmpDir}/${outputFileRoot}averageB0.nii.gz");
    
    # Get all b=0 data, and average
    
    # Then Rigid moco to average
    
    
    
    if ( ($distCorrRefImageType =~ m/meanb0/i) ) {
	# Do final moco of all data to mean b0
	
    }
    elsif ( ($distCorrRefImageType =~ m/meandwi/i) ) {

	my $its = 2;

	for (my $i = 0; $i < $its; $i++) {
	    # Compute mean DWI, align it to mean b0, moco all images to corrected mean DWI
	}
	
    }
    else {
	die "Unrecognized distortion correction target image type: $distCorrRefImageType");
    }

    
    system("averagedwi -schemefile $schemeMaster -minbval $minB_ForAverageDWI -maxbval $maxB_ForAverageDWI -inputfile $uncorrectedDWI_Master -outputfile ${tmpDir}/${outputFileRoot}meanDWI.nii.gz");  
    

    system("${antsDir}/antsMotionCorr -d 3 -a $outputDWI -o $ref");
    
    system("${antsDir}/antsMotionCorr -d 3 -m MI[${outputDir}/${outputFileRoot}ref.nii.gz,${outputDWI}, 1, 32, Regular, 0.125] -u 1 -t Affine[0.2] -i 25 -e 1 -f 1 -s 0 -l 0 -o [${outputDir}/${outputFileRoot}, ${outputDWI}, $ref ]");
    
# Correct directions via motion correction parameters
    print( "Correcting directions stored in $bvecMaster\n" );
    my $correctedScheme = "${outputDir}/${outputFileRoot}corrected.scheme";
    my $bvecCorrected = "${outputDir}/${outputFileRoot}corrected.bvec";
    my $correctDirections = "${antsDir}/antsMotionCorrDiffusionDirection --bvec $bvecMaster --output $bvecCorrected --moco ${outputDir}/${outputFileRoot}MOCOparams.csv --physical ${ref}";
    print( "$correctDirections\n");
    system($correctDirections);
    
    system("${caminoDir}/fsl2scheme -bscale 1 -bvals $bvalMaster -bvecs $bvecCorrected > $correctedScheme");
   

}
