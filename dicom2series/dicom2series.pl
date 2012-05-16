#!/usr/bin/perl -w
#
# Take a bunch of dicom files and sort them into a pipedream friendly format.
#

use strict;
use File::Basename;
use File::Path;
use File::Copy;
use FindBin qw($Bin);


my $usage = qq {
  Usage: dicom2series <output_dir> <empty_fields> <rename_files> <dicom_file1> ... <dicomfileN>

    <output_dir> - output base directory, which should be equal to the subject's unique identifier
 
    <empty_fields> - 1 if you want to empty certain fields the output, 0 otherwise. If 1, fields listed in the config file
      pipedream/config/dicomFieldsToEmpty.txt will be emptied in the output. The input is unchanged. This option is deliberately
      not named "anonymize" because there are multiple definitions of what it means to anonymize a dicom header. You should check
      the config file and add fields that should be removed in order to protect subject confidentiality. 

    <rename_files> - 1 if you want to rename files (if possible) in the output directory, 0 otherwise.

 
    dicom2series requires that all input DICOM files pertain to the same subject. That is, you need to call dicom2series
    separately for each subject's data. It is not necessary to separate data from the same subject by time point; that will
    be done automatically. If the input contains both DICOM and non DICOM files, the non DICOM files will be ignored.
      

    Example: 

      dicom2series.sh /home/user/data/subjectsDICOM/subject 1 0 /home/user/data/raw/subject/dicom/*

    White space and special characters in the series / file names will be removed or replaced with underscores.

    Because of Unix command line limits, you may need xargs to process large numbers of files:

      find -L <input_dir> -type f -print0 | xargs -0 dicom2series.sh <output_dir> <empty_fields> <rename_files>

    where input_dir contains DICOM files for this particular subject only.


    Output will be sorted into separate directories named by acquisition date and time.  
    Within each time point scans will be named according to the series number, protocol name, and series description.

    Input files compressed with GZIP will be decompressed on the fly. The input directories must be writeable
    if the files are compressed, but the files themselves will not be modified. Input files compressed with other algorithms
    (eg .zip or .bz2 files) must be decompressed before running dicom2series.
     
};


if (!($#ARGV + 1)) {
    print "$usage\n";
    exit 0;
}
elsif ($#ARGV < 4) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}

my ($outputDir, $anonymize, $renameFiles, @dicomFiles) = @ARGV;

my $gdcmDir = $ENV{'GDCMPATH'};

if ( ! -d "${outputDir}" ) {
    mkpath("${outputDir}", {verbose => 1}) or die "cannot create output directory ${outputDir}";
}

my $anonString = "--dumb ";

if ($anonymize) {
    my @lines = `cat ${Bin}/../config/dicomFieldsToEmpty.txt`;

    my @fields;

    foreach my $line (@lines) {
 
      $line =~ s/\s//g;

      if ($line =~ m/^\((\d+,\d+)\)/) {

        my $field = $1;

        push @fields, $field;

        $anonString = $anonString . " --empty $field ";
      }
   }

    print "  Emptying the following dicom fields: \n\t" . join("\n\t", @fields) . "\n\n";
     
} 


# Array of files that cannot be correctly converted, typically due to missing header information
my @problemFiles;


foreach my $dicomFile (@dicomFiles) {

    my ($isDicom, $missingInfo, $timepoint, $seriesDir, $newFileName) = getFileInfo($dicomFile, $renameFiles);

    # Make sure file really is dicom
    if (!$isDicom) {
	print "Skipping non DICOM file $dicomFile\n";
	next;
    }

    if ($missingInfo) {
	push(@problemFiles, $dicomFile);
	print "  WARNING: Insufficient header information to process $dicomFile - missing series description, series number or acquisition date\n";
	next;
    }
    

    if ( ! -d "${outputDir}/${timepoint}/${seriesDir}" ) {
	mkpath("${outputDir}/${timepoint}/${seriesDir}") or die "  Cannot create series directory ${outputDir}/${seriesDir}";
    }

    if ( -f "${outputDir}/${timepoint}/${seriesDir}/${newFileName}" ) {
	print "  WARNING: Multiple files map to ${outputDir}/${timepoint}/${seriesDir}/${newFileName}\n";

	push(@problemFiles, $dicomFile);
    }
    else {
	print "$dicomFile -> ${outputDir}/${timepoint}/${seriesDir}/${newFileName}\n";
	
        if ($anonymize) {
	    my $notOK = system("${gdcmDir}/gdcmanon -i \"$dicomFile\" -o ${outputDir}/${timepoint}/${seriesDir}/${newFileName} $anonString"); 
            
            if ($notOK) {
              die "gdcmanon returned non-zero exit code - fields may not have been correctly emptied\n";
            }
	}
	else {
	    copy($dicomFile, "${outputDir}/${timepoint}/${seriesDir}/${newFileName}") or die "Cannot copy files";
	}
    }

}

if ($#problemFiles > -1) {

    print "\nThe following dicom files could not be processed:\n";

    foreach my $problemFile (@problemFiles) {
	print "  $problemFile\n";
    }

    print "\n  WARNING: Some dicom files could not be processed, most likely due to missing header information\n\n";
    
}


#
# (isDICOM, missingInfo, acquisitionDate, seriesDir, newFileName) = getFileInfo($dcmFile, $renameFiles)
#
# If file is not DICOM, return an array of zeros.
#
# The new file name is either the original file name, or InstanceNumber_SeriesNumber_ProtocolName. 
# If header data is missing, the old file name is preserved. If the information is available, the 
# file is renamed if $renameFiles == 1.
#
sub getFileInfo {

    my ($dcmFile, $renameFiles) = @_;
    
    # parse the file name
    my ($fileBaseName, $dirName, $fileExtension) = fileparse($dcmFile, '\.[^.]*');

    my $header;

    if ($fileExtension eq ".gz") {
        my $uncompressed = "${dirName}/${fileBaseName}";

        `gunzip -c $dcmFile > "$uncompressed"`;

        $header = `${gdcmDir}/gdcmdump "$uncompressed" 2> /dev/null`; 
        
        `rm -f "$uncompressed"`; 
    }       
    else {
      $header = `${gdcmDir}/gdcmdump "$dcmFile" 2> /dev/null`;
    }

    my $isDicom = 1;

    if ( !( $header =~ m/# Dicom-File-Format/ ) ) {
	$isDicom = 0;

	return (0, 0, 0, 0, 0);
    }
    
    # What to return if we can't map this file sensibly
    my @missingInfo = (1, 1, 0, 0, 0);
    

    $header =~ m/\s*\(0008,0020\) DA \[(\d+)/ or return @missingInfo;

    my $acquisitionDate = $1;
    
    # Add underscores for readability goodness
    $acquisitionDate =~ s/(\d{4})(\d{2})(\d{2})/${1}_${2}_${3}/;

    # Add time
    $header =~ m/\s*\(0008,0030\) TM \[(\d{4})/ or return @missingInfo;

    $acquisitionDate = "${acquisitionDate}_$1";

    # Some headers have missing instance numbers, as a fallback use original file name
    my $acquisitionNumber = "";
    
    if ( $header =~ m/\s*\(0020,0013\) IS \[(\d+)/ ) {
	$acquisitionNumber = $1;
	$acquisitionNumber = sprintf("%.4d", $acquisitionNumber);
    }
    else {
	# Don't complain about this, but do not rename file if we don't have an instance number.
	$renameFiles = 0;
    }
    
    $header =~ m/\s*\(0020,0011\) IS \[(\d+)/ or return @missingInfo;

    my $seriesNumber = $1;

    $seriesNumber = sprintf("%.4d", $seriesNumber);

    # Prefer protocol name and series description but proceed with one or the other
    $header =~ m/\s*\(0008,103e\) LO \[([^\]]+)\]/; 

    my $seriesDescription = trim($1);

    $header =~ m/\s*\(0018,1030\) LO \[([^\]]+)\]/; 

    my $protocolName = trim($1);

    if (!($seriesDescription or $protocolName)) {
      return @missingInfo;
    }

    # If missing one, set to the other (only one gets used if they're the same)

    if (! $seriesDescription) {
	$seriesDescription = $protocolName;
    }
    elsif (! $protocolName) {
        $protocolName = $seriesDescription;
    }


    # Allow [\w] in protocol names, nothing else
    # [\s,-] -> underscore.
    $protocolName =~ s/[,\s-]+/_/g;
    $protocolName =~ s/[^\w]//g;
    $protocolName =~ s/_+/_/g;

    $seriesDescription =~ s/[,\s-]+/_/g;
    $seriesDescription =~ s/[^\w]//g;
    $seriesDescription =~ s/_+/_/g;

    my $seriesDir = join('_', $seriesNumber, $protocolName);

    if (!($seriesDescription eq $protocolName)) {
        # Append series description

        # If series description is protocol name followed by something else, don't repeat protocol name
        # Often the case for DTI

        $seriesDescription =~ s/^${protocolName}_?//;
	
        $seriesDir = "${seriesDir}_${seriesDescription}";
    }
    
    my $newFileName = $fileBaseName . $fileExtension;
    
    if ( $renameFiles ) {
	$newFileName = join('_', $acquisitionNumber, $seriesNumber, $protocolName);
	
	# Preserve file extension if it indicates compression
	if ( $fileExtension =~ m/gz/i ) {
	    $newFileName = $newFileName . $fileExtension;
	}
    }

    # Remove special characters that can mess up unix
    #
    # \s and , -> underscore. Allow dashes. Everything else goes away
    $newFileName =~ s/[,\s-]+/_/g;

    # Begone, you demons of stupid file naming!
    $newFileName =~ s/[^\.\w]//g;


    # Finally, clear up multiple underscores
    $newFileName =~ s/_+/_/g;

    return (${isDicom}, 0, ${acquisitionDate}, ${seriesDir}, ${newFileName});
    
}



sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    return $string;
}   

