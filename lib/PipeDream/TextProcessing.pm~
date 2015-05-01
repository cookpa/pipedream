package PipeDream::Dependencies;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(haveCamino haveANTs haveGDCM haveDCM2NII); # exported by default, 
@EXPORT_OK   = (); # Functions we will export on demand

sub haveCamino  { 
    
    return checkDependency("Camino", "dtfit");

}


sub haveANTs  { 

  return checkDependency("ANTs", "antsRegistration");
    
}

sub haveGDCM {

    my $gotProg = checkDependency("GDCM", "gdcmdump");    

    my $gdcmResourcesPath = @ENV{'GDCM_RESOURCES_PATH'};

    if (! -d $gdcmResourcesPath) {
	print STDERR "\nWarning: GDCM_RESOURCES_PATH not found, some gdcm functionality may be unavailable\n";
    }

    return $gotProg;
   
}

sub haveDCM2NII {
     return checkDependency("dcm2nii", "dcm2nii");
}


# checkProg($tool, $prog)
#
# Checks for $prog on PATH. Returns 1 if found, otherwise complains that it can't find 
# $tool, and returns 0.
#
sub checkDependency {

    my ($tool, $prog) = @_;

    my $progPath = `which $prog`;
    
    chomp($progPath);
    
    if ( -f $progPath ) {
	return 1;
    }
    else {
	print STDERR "\nCannot find $tool on PATH\n";
	return 0;
    }

}

1;
