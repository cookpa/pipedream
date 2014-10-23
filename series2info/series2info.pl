#!/usr/bin/perl -w

use strict;

use Cwd 'realpath';

use File::Path;
use File::Spec;
use File::Basename;
use FindBin qw($Bin);

my $usage = qq{
  Usage: series2info.pl <subject_list> <data_dir> <output_dir>

    <subject_list> - Text file containing a list of subject names.

    <data_dir> - Base input directory, in which we will look for data organized by subject ID as specified in the subject list.
      data_dir/subject_ID will be searched recursively for DICOM files and should contain only dicom files for one subject.

    <output_dir> - output base directory

  };


if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 2) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}

my ($subjectList, $inputBaseDir, $outputBaseDir) = @ARGV;

my $gdcmDir = $ENV{'GDCMPATH'};

# Convert I/O directories to absolute paths (needed for cluster)
$inputBaseDir = File::Spec->rel2abs($inputBaseDir);
$outputBaseDir = File::Spec->rel2abs($outputBaseDir);

# Eliminate ../ and such
$inputBaseDir = realpath($inputBaseDir);
$outputBaseDir = realpath($outputBaseDir);

if ( ! -d $outputBaseDir ) {
  mkpath($outputBaseDir, {verbose => 0, mode => 0755}) or die "Can't create output directory $outputBaseDir\n\t";
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



foreach my $subject (@subjects) {

    print( "Looking at $subject \n");

    my $subjOutputBaseDir = "${outputBaseDir}/${subject}/";
	  my $subjInputBaseDir = "${inputBaseDir}/${subject}/";

    my @times = glob( "${subjInputBaseDir}/*" );
    chomp(@times);

    foreach my $time ( @times ) {
      my $iTime = basename( $time );

      my @seqs = glob( "${inputBaseDir}/${subject}/${iTime}/*");
      chomp(@seqs);

      foreach my $seq ( @seqs ) {
        my $iSeq = basename( $seq );
        my @files = glob( "${inputBaseDir}/${subject}/${iTime}/${iSeq}/*");
        chomp(@files);

        my $outputDir = "${outputBaseDir}/${subject}/${iTime}/${iSeq}";
        if ( ! -d "${outputDir}" ) {
          mkpath("${outputDir}", {verbose => 1}) or die "cannot create output directory ${outputDir}";
        }

        my $cmd = "${gdcmDir}/gdcmdump $files[0] > ${outputDir}/${subject}_${iTime}_${iSeq}.txt";
        system($cmd);
        #print( "$cmd \n");

      }

    }


}


sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    return $string;
}
