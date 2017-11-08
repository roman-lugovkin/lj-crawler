use warnings;
use strict;
use utf8;
use Encode;

no warnings 'utf8';

$| = 1;

sub read_dir(@);

my @files = grep { /href\./ } read_dir('./data');
my $TOP = {};
my $fc = 0;
foreach ( @files ) {
    $fc ++;
    print "$fc. $_\n";
    open FP, "<$_";
    while (<FP>) {
        s/(\r|\n)//gsm;
        my @line = split(/\t/, $_);
        my $uname = shift @line;
        shift @line;
        shift @line;
        foreach ( @line ) {
            if ( /livejournal/ ) {
                unless ( index( $_, $uname ) > 0 ) {
                    if ( /\d+\.html$/ ) {
                        $TOP->{$_} ++;
                    }
                }
            }
        }
    }
    close FP;
}

open OUT, ">href.top.txt";
foreach ( sort { $TOP->{$b} <=> $TOP->{$a} } keys (%{$TOP}) ) {
    print OUT $_, "\t", $TOP->{$_}, "\n";
}
close OUT;

exit;

sub read_dir( @ ) {
    my $dir = shift;
    my @files;

    return @files unless ( -e $dir );

    opendir( DIR, $dir );
    my @dir = readdir DIR;
    closedir DIR;

    foreach ( @dir ) {
        next if ( /^\./ );
        my $name = $dir.'/'.$_;
        if ( -d $name ) {
            push @files, read_dir( $name );
        }
        else {
            if ( -e $name ) {
                push @files, $name;
            }
        }
    }

    return @files;
}

