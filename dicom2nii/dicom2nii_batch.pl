#!/usr/bin/perl -w

use strict;

use Cwd 'realpath';

use File::Path;
use File::Spec;
use FindBin qw($Bin);

my $usage = qq{
  Usage: dicom2nii <queue_type> <subject_list> <protocol_list> <data_dir> <output_dir> [output_sub_dir=rawNii]

      <queue_type> - type of queue to submit jobs. Either "sge", "voxbo", or "none"

      <subject_list> - Text file containing a list of subject names.

      <protocol_list> - Text file containing protocol names, eg 

        t1_mpr_AX_MPRAGE    
        t1_cor_MPRAGE

      All series from matching protocols will be processed.

      <data_dir> - Base input directory, in which we will look for data organized by subject/timepoint/protocol
      as produced by dicom2series
      
      DICOM data will be converted to nii:

          subject_timepoint_[series number]_[protocol name].nii.gz

      <output_dir> - output base directory. Output is placed into

      <output_sub_dir> - output directory within timepoint

	  output_dir/subject/timepoint/output_sub_dir/

  };


if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 4) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}


my ($qsub, $vbbatch) = @ENV{'PIPEDREAMQSUB', 'PIPEDREAMVBBATCH'};

my ($queueType, $subjectList, $protocolList, $inputBaseDir, $outputBaseDir, $outputSubDir) = @ARGV;

if (!$outputSubDir) {
  $outputSubDir = "rawNii";
}

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

my $userName = `whoami`;
chomp($userName);
my $queueName = $userName . "_pddcm2nii";



# Convert things to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);
$outputBaseDir = File::Spec->rel2abs($outputBaseDir);
$protocolList = File::Spec->rel2abs($protocolList);

# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);
$outputBaseDir = realpath($outputBaseDir);
$protocolList = realpath($protocolList);

if ( ! -d $outputBaseDir ) { 
    mkpath($outputBaseDir, {verbose => 0, mode => 0775}) or die "ERROR: Can't create output directory $outputBaseDir\n\t";
}

# Loop over all subjects and time points in the usual way, submit jorbs

# @timepoints is 2D array, each element is array of time points for each subj
my (@subjects, @timePoints);

# Process subject list
open SUBJFILE, "<$subjectList" or die "Can't find subject list file $subjectList";

while (<SUBJFILE>) {
    
    my $line = $_;

    my @tokens = split('\s+', trim($line));

    # Skip blank lines
    if (scalar(@tokens)) {
	my $subject = $tokens[0];

	shift @tokens;
	
	push(@subjects, $subject);
	
	if (!scalar(@tokens)) {
	    # Process all available time points
	    @tokens = `ls ${inputBaseDir}/${subject}`;
	    chomp(@tokens); 
	}	
	# else use time point(s) specified in file
	push(@timePoints, [ @tokens ]);
    }

}

close SUBJFILE;


if ($useVoxbo) {
    system("$vbbatch -f $queueName FILE");
}


foreach my $subjectCounter (0 .. $#subjects) {

  my $subject = $subjects[$subjectCounter];

  # reference to array of time points
  my $subjectTP = $timePoints[$subjectCounter];
    
  TIMEPOINT: foreach my $timePoint (@$subjectTP) {
      
    my $foundData = 0;

    my @dirContents = `ls ${inputBaseDir}/${subject}/${timePoint}`;

    my $tpOutputDir = "${outputBaseDir}/${subject}/${timePoint}/${outputSubDir}";

    # On clusters, simultaneous attempts to run dcm2nii can fail. We try to avoid this with a random sleep on each job
    #    my $delay = ($useVoxbo || $useSGE);
    # 
    # Possible we can avoid this by having each job make its own copy of the ini file. Disable delay for now
    #
    my $delay = 0;

    if (! -d $tpOutputDir ) {
	mkpath($tpOutputDir, {verbose => 0, mode => 0775}) or die "Can't make output directory $tpOutputDir\n\t";
    }
    
    my $cmd = "${Bin}/dicom2nii_q_subj.sh ${Bin} ${inputBaseDir} ${subject} ${timePoint} ${protocolList} ${tpOutputDir} $ENV{'HOME'} $delay";

    my $job = $cmd;
 
    if ($useVoxbo) { 
      $job = "$vbbatch -sn $queueName -a $queueName -c \"$cmd\" FILE";
    }
    elsif ($useSGE) {
      $job = "$qsub -S /bin/bash -j y -o ${tpOutputDir}/dicom2nii.stdout $cmd";
      # sleep to avoid qsub issues
      `sleep 0.5`;
    }
    
    system($job);
              
  }

}
   
# Starts queue, good luck
if ($useVoxbo) {
    system("$vbbatch -s $queueName");
}




sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;    
    $string =~ s/\s+$//;
    
    return $string;
}
