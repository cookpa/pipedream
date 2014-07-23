#!/usr/bin/perl -w
#
# Convert DICOM to nii
#

my $usage = qq{
dicom2nii.sh converts dicom series to NIFTI images, doesn't do any addition preprocessing

Usage: dicom2nii.sh <input_base_dir> <subject> <timepoint> <protocol_list> <outputDir>

<input_base_dir> - input directory Program looks for scans matching <input_dir>/<subject>/<timepoint>/<series_dir>

<subject> - subject ID

<timepoint> - Time point ID

<protocol_list> - Text file containing protocol names, eg 

      t1_mpr_AX_MPRAGE    
      t1_cor_MPRAGE

      All series from matching protocols will be processed.

<outputDir> - Base output directory

};

use strict;
use FindBin qw($Bin);
use File::Path;
use File::Spec;

my $inputBaseDir = "";

my $subject = "";

my $timepoint = "";

my $protocolFile = "";


# # Output directory
my $outputDir = "";


my ($antsDir, $dcm2niiDir) = @ENV{'ANTSPATH', 'DCM2NIIPATH'};

#Process command line args
if (($#ARGV != 4)) {
    print "$usage\n";
    exit 0;
}
else {

    ($inputBaseDir, $subject, $timepoint, $protocolFile, $outputDir) = @ARGV;

}
# done with args

if (! -d $outputDir ) {
    mkpath($outputDir, {verbose => 0, mode => 0755}) or die "Can't make output directory $outputDir\n\t";
}

open PROTOFILE, "<$protocolFile" or die "Can't find protocol list file $protocolFile";

my @protocols;
my @protocolNames;

while (<PROTOFILE>) {

    my $line = $_;    

    chomp $line;

    $line = trim($line);

    # ignore blank lines
    if ($line) {
        my @lineparts = split(" ", $line);
        push(@protocols, trim($lineparts[0]));
        push(@protocolNames, trim($lineparts[1]));
    }

}

close PROTOFILE;

my @dirContents = `ls ${inputBaseDir}/${subject}/${timepoint}`;

PROTOCOL: foreach my $protocolName (@protocols) {

  my $foundProtocol = 0;

  foreach my $subdir (@dirContents) {
    if ( $subdir =~ m|^([0-9]+_${protocolName})/?$|m) {

      $foundProtocol = 1;

      my $seriesName = $1;
      
      print "Transfering DICOM files for scan ${seriesName}\n";

      my $outputFileRoot = "${subject}_${timepoint}_${seriesName}";

      my $seriesDir = "${inputBaseDir}/${subject}/${timepoint}/${seriesName}";

      my $tmpDir = "${outputDir}/${outputFileRoot}tmp";

      mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Can't make working directory $tmpDir\n\t";

      my @imageFiles = `ls $seriesDir`;

      foreach my $inputFile (@imageFiles) {
        chomp $inputFile;

        # Assume only dicom files present
    
        if ($inputFile =~ m/\.gz$/) {
          my $decomp = $inputFile;
          $decomp =~ s/\.gz$//;
          `gunzip -c ${seriesDir}/${inputFile} > ${tmpDir}/$decomp`;
        }
        else {
          `cp ${seriesDir}/$inputFile ${tmpDir}/$inputFile`;
        }
      }
    
      # run dcm2nii - will output to $tmpDir
      my $dcm2niiOutput = `${dcm2niiDir}/dcm2nii -b ${Bin}/../config/dcm2nii.ini -r n -a n -d n -e y -f y -g n -i n -n y -p y $tmpDir`;

      $dcm2niiOutput =~ m/->(.*\.nii)/;
      my $niftiDataFile = $1;

      # Look for warnings in the dicom conversion
      if ($dcm2niiOutput =~ m/Warning:/ || $dcm2niiOutput =~ m/Error/) {
          print "\nDICOM conversion failed. dcm2nii output follows\n";
    
          print "\n${dcm2niiOutput}\n\n";
    
          exit 1;
      }

      `mv ${tmpDir}/$niftiDataFile ${outputDir}/${outputFileRoot}.nii`;
      `gzip ${outputDir}/${outputFileRoot}.nii`;

      # Copy DTI gradient info

      my $bvecFile = $niftiDataFile;

      $bvecFile =~ s/\.nii/\.bvec/;

      if (-f "${tmpDir}/$bvecFile") {
        my $bvalFile = $bvecFile;

        $bvalFile =~ s/\.bvec/\.bval/;

        `mv ${tmpDir}/$bvecFile ${outputDir}/${outputFileRoot}.bvec`;
        `mv ${tmpDir}/$bvalFile ${outputDir}/${outputFileRoot}.bval`; 
      }

      `rm -rf $tmpDir`;
      
    }

  }

  if (!$foundProtocol) {
    print "No match for $protocolName\n"; 
  }

}

sub trim {

    my ($string) = @_;

    if (!$string) {
      return $string;
    }

    $string =~ s/^\s+//;    
    $string =~ s/\s+$//;
    
    return $string;
}

