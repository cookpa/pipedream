#!/usr/bin/perl -w

use strict;

use Cwd 'realpath';

use File::Path;
use File::Spec;
use FindBin qw($Bin);

my $usage = qq{
  Usage: dicom2series_batch.sh <queue_type> <subject_list> <data_dir> <output_dir> [emptyFields] [rename] [vb_name]

    <queue_type> - type of queue to submit jobs. Either "sge", "voxbo", or "none" to run serially.

      This command is quite I/O intensive, so exercise caution when submitting many jobs on systems with shared I/O resources.

    <subject_list> - Text file containing a list of subject names.

    <data_dir> - Base input directory, in which we will look for data organized by subject ID as specified in the subject list.
      data_dir/subject_ID will be searched recursively for DICOM files and should contain only dicom files for one subject.
      
    output_dir> - output base directory

    [emptyFields] - 1 if you want to empty certain fields the output, 0 otherwise. If 1, fields listed in the config file
      pipedream/config/dicomFieldsToEmpty.txt will be emptied in the output. The input is unchanged. This option is deliberately
      not named "anonymize" because there are multiple definitions of what it means to anonymize a dicom header. You should check
      the config file and add fields that should be removed in order to protect subject confidentiality.

    [rename] - 1 if you want to rename files (if possible) in the output directory, 0 otherwise.

    White space and special characters in the series / file names will be removed or replaced with underscores.

    Output will be sorted into separate directories named by acquisition date. Within each date scans will be named according
    to the series number, protocol name, and series description.

    Input files compressed with GZIP will be decompressed on the fly. The input directories must be writeable
    if the files are compressed, but the files themselves will not be modified. Input files compressed with other algorithms
    (eg .zip or .bz2 files) must be decompressed before running dicom2series.

    [vb_name] - optional private queue name for voxbo.      
      
  };


if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 3) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}

my ($qsub, $vbbatch) = @ENV{'PIPEDREAMQSUB', 'PIPEDREAMVBBATCH'};

my ($queueType, $subjectList, $inputBaseDir, $outputBaseDir, $anon, $rename, $queueName) = @ARGV;

# These get used as args so have to have a value
if (!$anon) {
   $anon = 0;
}
if (!$rename) {
   $rename = 0;
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

if (! $queueName ) {
    my $userName = `whoami`;
    chomp($userName);
    $queueName =  $userName . "_pddcm2series";
}


# Convert I/O directories to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);
$outputBaseDir = File::Spec->rel2abs($outputBaseDir);

# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);
$outputBaseDir = realpath($outputBaseDir);

if ( ! -d $outputBaseDir ) { 
    mkpath($outputBaseDir, {verbose => 0, mode => 0775}) or die "Can't create output directory $outputBaseDir\n\t";
}


# Loop over all subjects and time points in the usual way, submit jorbs
# lists of stuff. Subjects is a 1D array, timePoints is 2D, %protocols is associative
my (@subjects, @timePoints, %protocols);

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
    }

}

close SUBJFILE;


if ($useVoxbo) {
    system("vbbatch -f $queueName FILE");
}


foreach my $subject (@subjects) {

    print( "Looking at $subject \n");    
  
    my $subjOutputBaseDir = "${outputBaseDir}/${subject}/";
	    
    # Need a wrapper script here to call dicom2series at run time on the cluster
    my $cmd = "${Bin}/dicom2series_q_subj.sh ${Bin} $subjOutputBaseDir $anon $rename ${inputBaseDir}/${subject}";

    my $job = $cmd;
      
    print( "Running: $cmd\n" );
 
    if ($useVoxbo) { 
      $job = "$vbbatch -sn $queueName -a $queueName -c \"$cmd\" FILE";
    }
    elsif ($useSGE) {
      $job = "$qsub -S /bin/bash $cmd";
      # sleep to avoid qsub issues
      `sleep 2`;
    }
    #print( "$job \n" );
    
    system($job);
      
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
