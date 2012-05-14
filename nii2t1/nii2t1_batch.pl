#!/usr/bin/perl -w

use strict;

use Cwd 'realpath';

use File::Path;
use File::Spec;
use FindBin qw($Bin);

my $usage = qq{
  Usage: nii2t1 <subject_list> <protocol_list> <data_dir> 


      <subject_list> - Text file containing a list of subject names, one per line, or a string for a single subject.

      <protocol_list> - Text file containing protocol names and short names, separated by whitespace, eg

        t1_mpr_AX_MPRAGE     mprage_t1
        t1_mpr_ns_AXIAL	     mprold_t1
      

      the short name is used in the output file names of nifti t1 data. It's good to include a common suffix 
      (usually _t1) so that all t1 scans can easily be listed via wildcard.

      <data_dir> - Base input directory, in which we will look for data organized by 
        subject/timepoint/rawNii/*protocol.nii.gz, as produced by dicom2nii.
      
      The output will be written to data_dir/subject/timepoint/T1. Nothing will be done if this directory already exists. 
      If you need to re-run nii2t1 for any reason, delete the T1 directory.

      Output will be named

        subject_timepoint_[short protocol name].nii.gz

      At most one image will be converted per matching protocol; repeat T1 scans will not be processed. 

  };


if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 2) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}


my ($subjectList, $protocolList, $inputBaseDir) = @ARGV;

# Convert I/O directories to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);

# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);

# Loop over all subjects and time points in the usual way, submit jorbs
# lists of stuff. Subjects is a 1D array, timePoints is 2D, %protocols is associative
my (@subjects, @timePoints, %protocols);

# Process subject list
if ( -s $subjectList) {

    open SUBJFILE, "<$subjectList" or die "Can't find subject list file $subjectList";
    
    while (<SUBJFILE>) {
	
	my $line = $_;
	
	my @tokens = split('\s+', trim($line));
	
	# Skip blank lines
	if (scalar(@tokens)) {
	    my $subject = $tokens[0];
	    
	    @tokens = `ls ${inputBaseDir}/${subject}`;
	    chomp(@tokens); 
	    push(@timePoints, [ @tokens ]);
	    
	    push(@subjects, $subject);
	}
	
    }

}
else {

    # single subject

    print "Processing $subjectList as a single subject ID\n";

    push(@subjects, $subjectList);

}

close SUBJFILE;

open PROTOFILE, "<$protocolList" or die "Can't find protocol list file $protocolList";

while (<PROTOFILE>) {

    my $line = $_;    

    my @tokens = split('\s+', trim($line));
    
    # ignore blank lines
    if (scalar(@tokens)) {
	my $protocolName = $tokens[0];
    
        # If user has not provided a short protocol, just use the protocol itself	
        if ($tokens[1]) {
            $protocols{$protocolName} = $tokens[1];
        }
        else {
            $protocols{$protocolName} = $protocolName;
        }
    }    
}

close PROTOFILE;


foreach my $subjectCounter (0 .. $#subjects) {

    my $subject = $subjects[$subjectCounter];

    # reference to array of time points
    my $subjectTP = $timePoints[$subjectCounter];
    
  TIMEPOINT: foreach my $timePoint (@$subjectTP) {
      
      my $foundData = 0;

      my $dirContents = `ls ${inputBaseDir}/${subject}/${timePoint}/rawNii`;

      my $tpOutputBaseDir = "${inputBaseDir}/${subject}/${timePoint}/T1";

      if ( -d "$tpOutputBaseDir" ) {
        print "Output directory $tpOutputBaseDir already exists. Skipping this time point\n";
        next TIMEPOINT;
      }
      else {
	  mkpath($tpOutputBaseDir, {verbose => 0, mode => 0755}) or die "Cannot create output directory $tpOutputBaseDir\n";
      }
      
      
    PROTOCOL: foreach my $protocolName (keys %protocols) {

	my $shortProtocol = $protocols{$protocolName};
	
	my $image = "";

	if ( $dirContents =~ m|(^${subject}_${timePoint}_[0-9]+_${protocolName}.nii.gz)|m) {
	    $image = $1;
	    $foundData = 1;
            print "Found data for protocol ${protocolName}\n";
	}
	else { 
	    next PROTOCOL;
	}
	
	my $cmd = "cp ${inputBaseDir}/${subject}/${timePoint}/rawNii/$image ${inputBaseDir}/${subject}/${timePoint}/T1/${subject}_${timePoint}_${shortProtocol}.nii.gz";
	
	system($cmd);
        
    }
      
      if (!$foundData) {
	  print "Could not find any data for subject $subject time point $timePoint\n";
      }
      
  }

}


sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;    
    $string =~ s/\s+$//;
    
    return $string;
}
