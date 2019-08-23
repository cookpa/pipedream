#!/usr/bin/perl -w
#
# Take a bunch of dicom files and sort them into a pipedream friendly format.
#

use strict;
use File::Basename;
use File::Compare;
use File::Copy;
use File::Find;
use File::Path;
use FindBin qw($Bin);


my $usage = qq {
  Usage: dicom2series <output_dir> <empty_fields> <rename_files> <dicom_directory> 

    <output_dir> - output base directory, which should be equal to the subject's unique identifier
 
    <empty_fields> - 1 if you want to empty certain fields the output, 0 otherwise. If 1, fields listed in the config file
      pipedream/config/dicomFieldsToEmpty.txt will be emptied in the output. The input is unchanged. This option is deliberately
      not named "anonymize" because there are multiple definitions of what it means to anonymize a dicom header. You should check
      the config file and add fields that should be removed in order to protect subject confidentiality. 

      Private fields cannot be altered by gdcmanon. Some PACS systems will copy patient information into private fields where
      they can't be touched. Always check the output to ensure that the required fields were removed successfully.

    <rename_files> - 1 if you want to rename files in the output directory, 0 otherwise.

    <dicom_directory> - A directory that will be searched recursively for dicom files.

    dicom2series requires that all input DICOM files pertain to the same subject. That is, you need to call dicom2series
    separately for each subject's data. It is not necessary to separate data from the same subject by time point; that will
    be done automatically. If the input contains both DICOM and non DICOM files, the non DICOM files will be ignored.
 

    Example: 

      dicom2series.sh /home/user/data/subjectsDICOM/subject 1 0 /home/user/data/raw/subject/dicom/

    White space and special characters in the series / file names will be removed or replaced with underscores.

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
elsif ($#ARGV < 3) {
    die "ERROR: Missing arguments, run without args to see usage\n\t";
}

my ($outputDir, $anonymize, $renameFiles, $dicomDir) = @ARGV;

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

      if ($line =~ m/^\((.{4},.{4})\)/) {

        my $field = $1;

        push @fields, $field;
 
        $anonString = $anonString . " --empty $field ";
      }
   }

    print "  anon string \n $anonString \n\n Emptying the following dicom fields: \n\t" . join("\n\t", @fields) . "\n\n";
     
} 


# Array of DICOM files that cannot be correctly converted, typically due to missing header information
my @problemFiles = ();

# Count how many dicom files were processed successfully for each series - this is often predictable for a particular acquisition
# Series defined as date/series_dir_name
my %dicomSeriesFileCounter = ();

# Just in case there are problems, store output file in a hash that looks up the original file
my %outputToInputMapping = ();

# Potential dicom files, will need to check them all
find({ wanted => \&processFile, no_chdir => 1, follow => 1}, $dicomDir);

print "\n\nFinished searching $dicomDir\n\nDICOM data manifest:\n\n";

print "Date,seriesNumber,seriesName,DicomFiles\n";

foreach my $seriesKey (sort(keys(%dicomSeriesFileCounter))) {

    my $seriesDataCSV = $seriesKey;

    # Map date/0000_someSeries to date,0000,someSeries
    $seriesDataCSV =~ s|/(\d\d\d\d)_|,${1},|g;

    print "$seriesDataCSV,$dicomSeriesFileCounter{$seriesKey}\n";
}

print "\n";
 

if ($#problemFiles > -1) {

    print "\nThe files below could not be processed successfully.\n\nError key:\n";
    print "  DUPLICATE_INPUT : Multiple copies of the same file are present within the input directory. The first one encountered is processed.\n"; 
    print "  MISSING_HEADER_INFO : Could not extract sufficient header information to map file to output. File not processed.\n"; 
    print "  OUTPUT_NAMING_COLLISION : Different files map to the same output. Conflicting files moved to a separate output directory. These conflicts must be resolved manually.\n"; 
    print "\nFile,Error\n";

    foreach my $problemFile (@problemFiles) {
	print "$problemFile\n";
    }
    
}


#
# processFile($aFile) deals with a potential dicom file. Called by find
#
sub processFile {

    my $aFile = $_;

    # First verify that it's really a regular file
    if (! -f $aFile) {
        return;
    }

    my ($isDicom, $missingInfo, $timepoint, $seriesDir, $newFileName) = getFileInfo($aFile, $renameFiles);

    # Make sure file really is dicom
    if (!$isDicom) {
	return;
    }

    my $dicomFile = $aFile;

    if ($missingInfo) {
	push(@problemFiles, "${dicomFile},MISSING_HEADER_INFO");
	print STDERR "  ERROR: Insufficient header information to process $dicomFile - missing series description, series number or acquisition date\n";
	return;
    }
    

    if ( ! -d "${outputDir}/${timepoint}/${seriesDir}" ) {
	mkpath("${outputDir}/${timepoint}/${seriesDir}") or die "  Cannot create series directory ${outputDir}/${seriesDir}";
	print "Creating series directory ${outputDir}/${timepoint}/${seriesDir}\n";
    }

    my $newFileWithPath = "${outputDir}/${timepoint}/${seriesDir}/${newFileName}";
    
    if ( exists $outputToInputMapping{$newFileWithPath} ) {
	print STDERR "  ERROR: Multiple files map to ${newFileWithPath}\n";
        
        # Compare to unanonymized "original" file, ie the one processed first which may or may not be the one the user wants
        my $originalOrIsIt = $outputToInputMapping{$newFileWithPath};
        
        if ( compare($originalOrIsIt,$dicomFile) == 0 ) {
            print STDERR "    Skipping $dicomFile : identical to $originalOrIsIt\n";
            push(@problemFiles, "${dicomFile},DUPLICATE_INPUT");
            return; 
        }
        else {
            
            # Files map to the same name, but are different - a more serious problem
            
            print STDERR "\n    ERROR: Different files map to the same output.\n    $dicomFile -> $newFileWithPath\n    conflicts with previous mapping\n    $originalOrIsIt -> $newFileWithPath\n\n";
            push(@problemFiles, "${dicomFile},OUTPUT_NAMING_COLLISION");

            # Dump the imposters to another directory
            # Rename series dir so these get counted separately below
            $seriesDir = "${seriesDir}_NamingConflicts";

            my $outputDirCollision = "${outputDir}/${timepoint}/${seriesDir}";

            if (! -d $outputDirCollision ) {
                mkpath($outputDirCollision) or die "  Cannot create series directory $outputDirCollision";
            }

            # Worst case scenario, there is multiple degeneracy in file names
            my $collisionCounter=1;

            $newFileWithPath = "${outputDirCollision}/conflict_${collisionCounter}_${newFileName}";

            while ( exists $outputToInputMapping{$newFileWithPath} ) {
                $collisionCounter++;
                $newFileWithPath = "${outputDirCollision}/conflict_${collisionCounter}_${newFileName}";
            }
        }
    }

    if ($anonymize) {

	my $anonCmd = "${gdcmDir}/gdcmanon -i \"$dicomFile\" -o $newFileWithPath $anonString";

        system($anonCmd); 
        
        my $notOK = $? >> 8;

        if ($notOK) {
            # Die immediately rather than continue with information not removed 
            die "gdcmanon returned non-zero exit code $notOK - fields may not have been correctly emptied. Call to gdcmanon was:\n$anonCmd\n";
        }
    }
    else {
        copy($dicomFile, "$newFileWithPath") or die "Cannot copy files";
    }
    
    $outputToInputMapping{$newFileWithPath} = $dicomFile;
    $dicomSeriesFileCounter{"${timepoint}/${seriesDir}"}++;
    

}


#
# (isDICOM, missingInfo, studyDate, seriesDir, newFileName) = getFileInfo($dcmFile, $renameFiles)
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
    
    # Data types can be different than expected, in which case gdcmdump will print
    # (0000,0000) ?? (DA) [Value] where the DA in parentheses is the expected data type
    # 
    # We match this with (?:\?\? \()?DA\)?

    $header =~ m/\s*\(0008,0020\) (?:\?\? \()?DA\)? \[(\d+)/ or return @missingInfo;

    my $studyDate = $1;
    
    # Add underscores for readability goodness
    $studyDate =~ s/(\d{4})(\d{2})(\d{2})/${1}_${2}_${3}/;

    # Add time
    $header =~ m/\s*\(0008,0030\) (?:\?\? \()?TM\)? \[(\d{4})/ or return @missingInfo;

    $studyDate = "${studyDate}_$1";

    # Sometimes series number contains spaces, eg you have [ 1] through [ 9] and then [10]
    $header =~ m/\s*\(0020,0011\) (?:\?\? \()?IS\)? \[\s*(\d+)/ or return @missingInfo;

    my $seriesNumber = $1;

    $seriesNumber = sprintf("%.4d", $seriesNumber);

    # Prefer protocol name and series description but proceed with one or the other
    $header =~ m/\s*\(0008,103e\) (?:\?\? \()?LO\)? \[([^\]]+)\]/; 

    my $seriesDescription = trim($1);

    $header =~ m/\s*\(0018,1030\) (?:\?\? \()?LO\)? \[([^\]]+)\]/; 

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
  
        my $extraDescription = "";
        
        if ($seriesDescription =~ m/${protocolName}/) {
            # If protocol name is substring of series description, don't repeat protocol name
            # Often the case for DTI
            $extraDescription = $seriesDescription;
            
            $extraDescription =~ s/${protocolName}//;
            
            # Clean up trailing or leading _
            $extraDescription =~ s/^_//;
            
            $extraDescription =~ s/_$//;

            # In case protocol name is in the middle
            $extraDescription =~ s/__/_/g;
        }
        elsif ($protocolName =~ m/${seriesDescription}/) {
            # If series description is a substring of protocol name, don't repeat it
            # nothing to add in this case
            $extraDescription = "";
        } 
        else {
            # Distinct protocol name and description, append both
            $extraDescription = $seriesDescription; 
        }
        
        if ($extraDescription) {
            $seriesDir = "${seriesDir}_${extraDescription}"; 
        }
    }
    
    my $newFileName = $fileBaseName . $fileExtension;

    if ( $renameFiles ) {

	# Rename to SOP UID - makes for ugly file names but anything nicer risks non-uniqueness

	my $sopUID = "";

        if ( $header =~ m/\s*\(0008,0018\) UI \[([0-9.]+)/ ) {
            $sopUID = $1;
        }

        if (!$sopUID) {
            print "Can't rename file - missing data in field (0008,0018)\n";
            return @missingInfo; 
        }

	$newFileName = $sopUID . ".dcm";

	# Preserve file extension if it indicates compression
	if ( $fileExtension =~ m/gz/i ) {
	    $newFileName = $newFileName . $fileExtension;
	}
    }
    else {
	# Remove special characters that can mess up unix
	#
	# replace common separators with underscore. Everything else goes away
	$newFileName =~ s/[,\s-]+/_/g;
	
	# replace anything not a word character (includes _) or a period
	$newFileName =~ s/[^\.\w]//g;

	# Finally, clear up multiple underscores
	$newFileName =~ s/_+/_/g;
    }

    return (${isDicom}, 0, ${studyDate}, ${seriesDir}, ${newFileName});
    
}



sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    return $string;
}   

