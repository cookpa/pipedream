#!/usr/bin/perl -w


use strict;

use Cwd 'realpath';

use FindBin qw($Bin);

use File::Path;

my $usage = qq{
    
 nii2dt <queue_type> <subject_list> <protocol_list> <data_dir> 


        <queue_type> - type of queue to submit jobs. Either "sge", "voxbo", or "none"


	<subject_list> - File containing the subject list, or a string identifying a single subject


	<protocol_list> - The protocol list file. Contains a list of actual protocol names and their short form. 
	  The short form is prepended onto the output files. All matching protocols are is processed, so it is 
          important to provide unique short protocol names to avoid confusion. Example:

          DTI_30dir_noDiCo_vox2_1000    30dir_dt       /path/to/template.nii.gz    /path/to/templatemask.nii.gz 
	  ep2d_diff_MDDW_12             12dir_dt       /path/to/template.nii.gz    /path/to/templatemask.nii.gz 
	
        The template / brain mask are an average DWI template. If you don't have one of these, no brain extraction
        will be performed. However you can use the average DWI images to create a template, then re-run this script.
 
        Different protocols can often share the same template, since the average DWI image often looks similar across
        protocols. The quality of brain extraction should always be checked.

	The protocol list may optionally specify bval and bvec files for a protocol, eg

 	  ep2d_diff_MDDW_12  12dirdt  /path/to/template.nii.gz   /path/to/templatemask.nii.gz  /path/to12dir.bval  /path/to12dir.bvec

        this option is used when the default bvals / bvecs extracted from dcm2nii are incorrect (rarely the case).


	
	<data_dir> - input directory. Program looks for scans matching the protocol name in data_dir/SUBJECT/TIMEPOINT/rawNii. 

};


my ($queueType, $subjectList, $protocolList, $inputBaseDir);

if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 3) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}
else { 
    ($queueType, $subjectList, $protocolList, $inputBaseDir) = @ARGV;

}

my ($qsub, $vbbatch) = @ENV{'PIPEDREAMQSUB', 'PIPEDREAMVBBATCH'};

# Convert I/O directories to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);


# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);


# for voxbo
my $userName = `whoami`;
chomp($userName);
my $queueName =  $userName . "_pddcm2dt";


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


# lists of stuff. Subjects is a 1D array, timePoints is 2D, %protocols, %bvals, %bvecs is associative
my (@subjects, @timePoints, %protocols, %bvals, %bvecs, %templates, %templateMasks);

# Process subject list
if ( -s $subjectList) {

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
	
	if (scalar(@tokens) > 2) {
	    # Get averageDWI template and brain mask
	    if (File::Spec->file_name_is_absolute($tokens[2])) {
		$templates{$protocolName} = $tokens[2];
	    }
	    else {
		$templates{$protocolName} = $protoVolume . $protoDirs . "/" . $tokens[3];
	    }
	    
	    if (File::Spec->file_name_is_absolute($tokens[3])) {
		$templateMasks{$protocolName} = $tokens[3];
	    }
	    else {
		$templateMasks{$protocolName} = $protoVolume . $protoDirs . "/" . $tokens[3];
	    }
	}
	if (scalar(@tokens) > 4) {
	    # Assume bvals / bvecs are specified relative to position of protocols.txt file
	    # unless they are absolute paths
	    if (File::Spec->file_name_is_absolute($tokens[4])) {
		$bvals{$protocolName} = $tokens[4];
	    }
	    else {
		$bvals{$protocolName} = $protoVolume . $protoDirs . "/" . $tokens[4];
	    }
	    
	    if (File::Spec->file_name_is_absolute($tokens[5])) {
		$bvecs{$protocolName} = $tokens[5];
	    }
	    else {
		$bvecs{$protocolName} = $protoVolume . $protoDirs . "/" . $tokens[5];
	    }
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
      
      my $outputDir = "${inputBaseDir}/${subject}/${timePoint}/DT";
      
      if ( -d "$outputDir" ) {
          print "Output directory $outputDir already exists. Skipping this time point\n";
          next TIMEPOINT;
      }
      else {
	  mkpath($outputDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $outputDir\n\t";
      }
      
      
    PROTOCOL: foreach my $protocolName (keys %protocols) {
	
 	my $protocolKey = 0;
	
	my $dirContents = `ls ${inputBaseDir}/${subject}/${timePoint}/rawNii`;
       
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

	my $schemeFiles = "";

	if ( defined($bvals{$protocolKey}) && -f $bvals{$protocolKey} ) {
	    $schemeFiles = "$bvals{$protocolKey} $bvecs{$protocolKey}";
	}
	else {
	   
           # Assume repeats have same scheme, grab first one
           
           my $bvalFile = `ls ${inputBaseDir}/${subject}/${timePoint}/rawNii/${subject}_${timePoint}_[0-9]*_${protocolName}.bval | head -n 1`;
           my $bvecFile = `ls ${inputBaseDir}/${subject}/${timePoint}/rawNii/${subject}_${timePoint}_[0-9]*_${protocolName}.bvec | head -n 1`;  
           
           chomp $bvalFile;
           chomp $bvecFile;

           $schemeFiles = "$bvalFile $bvecFile";
	}

	my $templatePaths = "none none";

	if ( defined($templates{$protocolKey}) ) {
	    $templatePaths = "$templates{$protocolKey} $templateMasks{$protocolKey}";
	}

	# Now get
	my @dwiImages = `ls ${inputBaseDir}/${subject}/${timePoint}/rawNii/${subject}_${timePoint}_[0-9]*_${protocolName}.nii.gz`;
	
        chomp @dwiImages;

	my $imageString = join(" ", @dwiImages);

	my $cmd = "${Bin}/nii2dt_q_subj.sh ${Bin} $ENV{'HOME'} $schemeFiles $templatePaths $outputDir $outputFileRoot $imageString";
	
	my $job = $cmd;

	if ($useVoxbo) { 
	    $job = "$vbbatch -sn $queueName -a $queueName -c \"$cmd\" FILE";
	}
	elsif ($useSGE) {
	    $job = "$qsub -S /bin/bash -o $ENV{'HOME'}/nii2dt_${subject}_${timePoint}_${protocolName}.stdout -e $ENV{'HOME'}/nii2dt_${subject}_${timePoint}_${protocolName}.stderr $cmd";
	    # sleep to avoid qsub issues
	    `sleep 1`;
	}
	
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
