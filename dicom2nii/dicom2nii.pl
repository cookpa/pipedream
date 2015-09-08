#!/usr/bin/perl -w
#
# Convert DICOM to nii
#

my $usage = qq{
dicom2nii.sh converts dicom series to NIFTI images, doesn't do any additional preprocessing

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
use File::Copy;
use File::Path;
use File::Spec;

my $inputBaseDir = "";

my $subject = "";

my $timepoint = "";

my $protocolFile = "";


# # Output directory
my $outputDir = "";

my ($antsDir, $dcm2niiDir, $tmpBaseDir) = @ENV{'ANTSPATH', 'DCM2NIIPATH', 'TMPDIR'};

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

  SUBDIR: foreach my $subdir (@dirContents) {

    chomp $subdir;

    if ( -d "${inputBaseDir}/${subject}/${timepoint}/${subdir}" && $subdir =~ m|^([0-9]+_${protocolName})/?$|m) {

      $foundProtocol = 1;

      # Includes number
      my $seriesName = $1;
      
      my $outputFileRoot = "${subject}_${timepoint}_${seriesName}";
 
      if ( -f "${outputDir}/${outputFileRoot}.nii.gz") {
        print "Output file ${outputDir}/${outputFileRoot}.nii.gz exists already; skipping this series\n";
        next SUBDIR; # Next subdir, might be others matching this protocol
      }

      print "Transfering DICOM files for scan ${seriesName}\n";
     
      my $seriesDir = "${inputBaseDir}/${subject}/${timepoint}/${seriesName}";

      my $tmpDir = "${outputDir}/${outputFileRoot}tmp";

      if ($tmpBaseDir && -d "$tmpBaseDir") {
        $tmpDir = "${tmpBaseDir}/${outputFileRoot}tmp";
      }

      # die if $tmpDir can't be created to avoid possible rm -rf of existing directory 
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
          copy("${seriesDir}/$inputFile", "${tmpDir}/$inputFile");
        }
      }
    
      # run dcm2nii - will output to $tmpDir
      
      my $tmpIni = "${tmpDir}/dcm2nii.ini";

      copy("${Bin}/../config/dcm2nii.ini", "$tmpIni");

      my $dcm2niiOutput = `${dcm2niiDir}/dcm2nii -b $tmpIni -r n -a n -d n -e y -f y -g n -i n -n y -p y $tmpDir`;

      my @niftiFiles = $dcm2niiOutput =~ m/->(.*\.nii)/g;

      if (scalar(@niftiFiles) > 1) {
          print "\nWARNING: Cannot process this series because multiple nii files were produced: @niftiFiles \n";
          next PROTOCOL;
      }


      # Look for warnings in the dicom conversion
      if ($dcm2niiOutput =~ m/Warning:/ || $dcm2niiOutput =~ m/Error/) {
          print "\nDICOM conversion failed or there were warnings. dcm2nii output follows\n";

          print "\n${dcm2niiOutput}\n\n";
    
          open FILE, ">${outputDir}/${outputFileRoot}_dcm2niiErrorsAndWarnings.txt";

          print FILE "${dcm2niiOutput}\n";

          close FILE;

          # Proceed if a nifti image got produced 
          if ( scalar(@niftiFiles) == 0 ) {
            next PROTOCOL;
          }
      }

      my $niftiDataFile = $niftiFiles[0];
     
      # Optionally gzip with higher compression than standard here. Slower, but
      # may be worthwhile for large data sets
      `gzip "${tmpDir}/$niftiDataFile"`;
 
      copy("${tmpDir}/${niftiDataFile}.gz", "${outputDir}/${outputFileRoot}.nii.gz");

      # Copy DTI gradient info

      my $bvecFile = $niftiDataFile;

      $bvecFile =~ s/\.nii/\.bvec/;

      if (-f "${tmpDir}/$bvecFile") {
        my $bvalFile = $bvecFile;

        $bvalFile =~ s/\.bvec/\.bval/;

        copy("${tmpDir}/$bvecFile", "${outputDir}/${outputFileRoot}.bvec");
        copy("${tmpDir}/$bvalFile", "${outputDir}/${outputFileRoot}.bval"); 
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

