use warnings;
use strict;
use utf8;
use Encode;

no warnings 'utf8';

$| = 1;

sub read_dir(@);

my @files = grep { /content\./ } read_dir('./data');
my $TOP = {};
my $T1 = {};
my $T2 = {};
my $fc = 0;
foreach ( @files ) {
    $fc ++;
    print "$fc. $_\n";
    open FP, "<$_";
    while (<FP>) {
        s/(\r|\n)//gsm;
        my $str = decode( 'utf-8', $_ );
        my @line = split(/\t/, $str);
        my $uname = $line[0] || '';
        my $text = $line[4] || '';
        if ( $text =~ /\sОригинал взят у ([^\s]+?) / ) {
            my $original = $1;
            $TOP->{$original}->{$uname} ++;
            $T1->{$uname} ++;
            $T2->{$original} ++;
        }
    }
    close FP;
}

open OUT, ">rep.target.txt";
foreach ( sort { $T1->{$b} <=> $T1->{$a} } keys (%{$T1}) ) {
    print OUT $_, "\t", $T1->{$_}, "\n";
}
close OUT;

open OUT, ">rep.source.txt";
foreach ( sort { $T2->{$b} <=> $T2->{$a} } keys (%{$T2}) ) {
    print OUT $_, "\t", $T2->{$_}, "\n";
}
close OUT;

open OUT, ">rep.all.txt";
foreach my $source ( sort { $T2->{$b} <=> $T2->{$a} } keys (%{$T2}) ) {
    my $SR = $TOP->{$source};
    foreach ( sort { $SR->{$b} <=> $SR->{$a} } keys( %{$SR} ) ) {
        print OUT join("\t", $source, $_, $SR->{$_}), "\n";
    }
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

