#!/usr/bin/perl -w


use strict;

use Cwd 'realpath';

use FindBin qw($Bin);

use File::Path;

my $usage = qq{
    
 nii2dt_batch <queue_type> <subject_list> <protocol_list> <input_base_dir> [input_dwi_dir = rawNii] [output_base_dir = input_base_dir] [output_dti_dir = DTI]


  Required args:


  <queue_type> - type of queue to submit jobs. Either "sge", "voxbo", or "none"


  <subject_list> - File containing the subject list, or a string identifying a single subject


  <protocol_list> - The protocol list file. Contains a list of actual protocol names and their short form. 
   The short form is prepended onto the output files . All matching protocols are is processed, so the short form
   must be unique.

   DTI_30dir_noDiCo_vox2_1000    30dir_dt       
   ep2d_diff_MDDW_12             12dir_dt       
	
   <input_base_dir> - input directory. Program looks for scans matching the protocol name in data_dir/SUBJECT/TIMEPOINT/input_dwi_dir. 


   Options:


   [input_dwi_dir] - modality specific subdirectory. Default: rawNii
  
   [output_base_dir] - directory to store DTI. Processed data will be placed in output_base_dir/SUBJECT/TIMEPOINT/output_dti_dir.
   Default: <input_base_dir>

   [output_dti_dir] - final subdirectory for output. Default: DTI

};


my ($queueType, $subjectList, $protocolList, $inputBaseDir, $inputSubDir, $outputBaseDir, $outputSubDir);

if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 4) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}
else { 
    ($queueType, $subjectList, $protocolList, $inputBaseDir, $inputSubDir, $outputBaseDir, $outputSubDir) = @ARGV;

}

# Some arg checking

my $useVoxbo = 0;
my $useSGE = 0;
my $useConsole = 0;

if ($queueType eq "voxbo") {
    $useVoxbo = 1;
}
elsif ($queueType eq "sge") {
    $useSGE = 1;
}
else {
    
    die "Unrecognized queue type $queueType" unless (uc($queueType) eq "NONE");
    $useConsole = 1;
}

# Allow subject to be a single subject string, so don't check it's a file

if ( ! -f $protocolList) {
    die "$protocolList is not a valid file name";
}

if ( ! -d $inputBaseDir ) {
    die "$inputBaseDir does not exist or is not a directory";
}


my ($qsub, $vbbatch) = @ENV{'PIPEDREAMQSUB', 'PIPEDREAMVBBATCH'};

# Convert I/O directories to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);


# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);

# Deal with options that may not be defined
if ( !length($inputSubDir) ) {
    $inputSubDir = "rawNii";
}


if ( !length($outputBaseDir) ) {
    $outputBaseDir = $inputBaseDir;
}

$outputBaseDir = File::Spec->rel2abs($outputBaseDir);
$outputBaseDir = realpath($outputBaseDir);

if (! -d $outputBaseDir ) {
   mkpath($outputBaseDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $outputBaseDir\n\t"; 
}

if ( !length($outputSubDir) ) {
    $outputSubDir = "DTI";
}

# for voxbo
my $userName = `whoami`;
chomp($userName);
my $queueName =  $userName . "_pddcm2dt";




# lists of stuff. Subjects is a 1D array, timePoints is 2D
my (@subjects, @timePoints, %protocols);

# Process subject list
if ( -e $subjectList) {

    open SUBJFILE, "<$subjectList" or die "Can't find subject list file $subjectList";
    
    while (<SUBJFILE>) {
	
	my $line = $_;
	
	my @tokens = split('\s+', trim($line));
	
	# Skip blank lines
	if (scalar(@tokens)) {
	    my $subject = $tokens[0];   
	    shift @tokens;
	    push(@subjects, $subject);
	    
	    @tokens = `ls ${inputBaseDir}/${subject}`;
	    chomp(@tokens); 
	    push(@timePoints, [ @tokens ]);
	}
    }
    close SUBJFILE;
}
else {    
    print "Processing $subjectList as a single subject ID\n";  
    push(@subjects, $subjectList);

    my @tokens = `ls ${inputBaseDir}/${subjectList}`;
    chomp(@tokens); 
    push(@timePoints, [ @tokens ]);
    
}

open PROTOFILE, "<$protocolList" or die "Can't find protocol list file $protocolList";
my ($protoVolume, $protoDirs, $protoFile) = File::Spec->splitpath( File::Spec->rel2abs($protocolList) );

while (<PROTOFILE>) {

    my $line = $_;    
    my @tokens = split('\s+', trim($line));
    
    # skip blank lines
    if (scalar(@tokens)) {

	my $protocolName = $tokens[0];
	
	if ($tokens[1]) {
	    $protocols{$protocolName} = $tokens[1];
	}
	else {
	    $protocols{$protocolName} = $tokens[0];
	}
    }
}

close PROTOFILE;

if ($useVoxbo) {
    `$vbbatch -f $queueName FILE`;
}

foreach my $subjectCounter (0 .. $#subjects) {
    
    my $subject = $subjects[$subjectCounter];
    
    # reference to array of time points
    my $subjectTP = $timePoints[$subjectCounter];
    
  TIMEPOINT: foreach my $timePoint (@$subjectTP) {
      
      my $foundData = 0;
      
      my $outputDir = "${outputBaseDir}/${subject}/${timePoint}/${outputSubDir}";
      
      if ( -d "$outputDir" ) {
          print "Output directory $outputDir already exists. Skipping this time point\n";
          next TIMEPOINT;
      }
      
    PROTOCOL: foreach my $protocolName (keys %protocols) {
	
	my $protocolKey = 0;
	
	my $dirContents = `ls ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir}`;
	
	if ( $dirContents =~ m|(^${subject}_${timePoint}_[0-9]+_${protocolName}.nii.gz)/?|m ) {
	    $protocolKey = $protocolName;
	    $foundData = 1;
	}
	else {
	    next PROTOCOL;
	}
	
	print "Found protocol $protocolKey for subject $subject time point $timePoint\n";
	
	my $shortProtocol = $protocols{$protocolKey};

	my $outputFileRoot = "${subject}_${timePoint}_${shortProtocol}_";

	my @bvalFiles = `ls ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir}/${subject}_${timePoint}_[0-9]*_${protocolName}.bval`;
	my @bvecFiles = `ls ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir}/${subject}_${timePoint}_[0-9]*_${protocolName}.bvec`;  
	
	chomp @bvalFiles;
	chomp @bvecFiles;
	
	# Now get DWI images
	my @dwiImages = `ls ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir}/${subject}_${timePoint}_[0-9]*_${protocolName}.nii.gz`;
	
	chomp @dwiImages;

	# Don't submit job if bvecs or bvals are missing
	if ( scalar(@bvalFiles) != scalar(@bvecFiles) ) {
	    print STDERR "Missing bval or bvec file in ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir} for protocol ${protocolName}\n";
	    next PROTOCOL;
	}
	if ( scalar(@bvalFiles) != scalar(@dwiImages) ) {
	    print STDERR "Number of bvals does not match number of images in ${inputBaseDir}/${subject}/${timePoint}/${inputSubDir} for protocol ${protocolName}\n";
	    next PROTOCOL;
	}

	# Make output dir so that SGE can put logs there
	mkpath($outputDir, {verbose => 0, mode => 0755});
	
	my $imageString = join(" ", @dwiImages);
	my $bvalString = join(" ", @bvalFiles);
	my $bvecString = join(" ", @bvecFiles);

	my $cmd = "${Bin}/nii2dt_q_subj.sh ${Bin} $ENV{'HOME'} --dwi $imageString --bvals $bvalString --bvecs $bvecString --outdir $outputDir --outroot $outputFileRoot --unweighted-bval 50";

	my $job = $cmd;

	if ($useVoxbo) { 
	    $job = "$vbbatch -sn $queueName -a $queueName -c \"$cmd\" FILE";
	}
	elsif ($useSGE) {
	    $job = "$qsub -S /bin/bash -o ${outputDir}/nii2dt_${subject}_${timePoint}_${protocolName}.stdout -e ${outputDir}/nii2dt_${subject}_${timePoint}_${protocolName}.stderr $cmd";
	    # sleep to avoid qsub issues
	    `sleep 0.5`;
	}
# 	print( "JOB: $job \n");
	system($job);
    }
      
      if (!$foundData) {
	  print "Could not find any data for subject $subject time point $timePoint\n";
      }
      
  }
}

    
# Starts queue, good luck
if ($useVoxbo) {
    print `$vbbatch -s $queueName`;
}




sub trim {
    
    my ($string) = @_;
    
    $string =~ s/^\s+//;    
    $string =~ s/\s+$//;
    
    return $string;
}
