package PipeDream::TextProcessing;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = (); # exported by default, 
@EXPORT_OK   = qw( trim ); # Functions we will export on demand


#
# Trims trailing or leading white space from a string
#
sub trim {

    my ($string) = @_;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    return $string;
}   


1;
