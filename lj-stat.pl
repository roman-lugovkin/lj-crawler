use warnings;
use strict;
use Statistics::Lite qw(:all);
use JSON;
use utf8;

$| = 1;

# v. 17.10.25

exit if ( !@ARGV );

my $DIR = './data/';

my @users;
print "Loading list...";
foreach my $IN ( @ARGV ) {
    open FP, "<$IN";
    while ( <FP> ) {
        s/(\n|\r)//gsm;
        my $user;
        eval {
            $user = from_json( $_ );
        };
        $user = {} unless ( defined $user );
        my $name = $user->{'user_name'} || $_ || ''; # Если вдруг этого поля нет, то мы пытаемся загрузить просто текстовый файл
        $name =~ s/_/\-/g;
        push @users, $name if ( $name );
    }
    close FP;
}
print "OK ", scalar( @users ), "\n";

my @head = (
    '#',
    'Журнал',
    'Постов',
    'Комментариев',
    'Комментаторов',
    'Комментариев без о.а.',
    'Слов',
    'Макс. ком. на пост',
    'Среднее ком. на пост',
    'Медиана ком. на пост',
    'Среднее слов',
    'Медиана слов',
    'Количество постов с ком.',
);

unlink "cmt.stat.csv";
open FP, ">lj.stat.csv";
print FP join( "\t", @head ), "\n";
close FP;    

my $CM = {};
my $CMOUT = {};
my $c_total = 0;
my $c_ok = 0;
my $uc = 0;
foreach my $uname ( @users ) {
    $uc ++;
    $c_total ++;
    my $cm_file = $DIR.'posts.'.$uname.'.json';
    unless ( -e $cm_file ) {
        $cm_file = $DIR.'cm.'.$uname.'.json';
    }
    
    # сначала загрузим текст
    my $TEXT = {};
    my $content_data_file = $DIR.'content.'.$uname.'.csv';
    
    $uname =~ s/\-/_/gsm;
    
    my $TITLES = {};
    if ( -e $content_data_file ) {
        open FP, "<$content_data_file";
        while (<FP>) {
            my @line = split( "\t", $_ );
            if ( $line[2] ) {
                my $text = $line[3].' '.$line[4];
                my @words = split( ' ', $text );
                $TEXT->{$line[1]} = scalar( @words );
                $TITLES->{$line[1]} = $line[3] || '';
            }
        }
        close FP;
    }

    my @stat = ( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 );

    my $POSTS = {};
    my $UCM = {};
    if ( -e $cm_file  ) {
        $c_ok ++;
        
        open FP, "<$cm_file";
        my @cms;
        while (<FP>) {
            my $TID = {};
            my @line = split( "\t", $_ );
            my $post_id = $line[1];
            my $post_time = $line[2];
            if ( $post_time ) {
                $stat[0] ++;
                push @cms, $line[3] || 0;
                if ( $line[3] ) {
                    $stat[10] ++;
                }
                
                my $data;
                eval {
                    $data = from_json( $line[5] );
                };
                
                if ( ref($data) eq 'ARRAY' ) {
                    foreach my $cm ( @{$data} ) {
                        if ( $cm->{'talkid'} and $cm->{'uname'} and ( !exists $TID->{ $cm->{'talkid'} } ) ) {
                            $UCM->{ $cm->{'uname'} } ++;
                            $TID->{ $cm->{'talkid'} } ++;
                        }
                    }
                }
            }

            if ( $line[3] and ( $line[3] > 2000 ) ) {
                open FP2, ">>lj.2000.csv";
                print FP2 $uname, "\t", $post_id, "\t", $line[3], "\t", 'https://'.$uname.'.livejournal.com/'.$post_id.'.html', "\t", $TITLES->{$post_id}, "\n";
                close FP2;
            }
        }
        close FP;
        
        foreach ( keys(%{$UCM}) ) {
            $CM->{$_} += $UCM->{$_};
        }
        
        $stat[1] = sum( values( %{$UCM} ) ) || 0;
        $stat[2] += scalar( keys %{$UCM} );
        delete $UCM->{ $uname };
        
        open FP2, ">>cmt.stat.csv";
        print FP2 $uname, " ", join( ", ", map { qq{$_($UCM->{$_})} } sort { $UCM->{$b} <=> $UCM->{$a} } keys( %{$UCM} ) ), "\n";
        close FP2;
        
        foreach ( keys(%{$UCM}) ) {
            $CMOUT->{$_} += $UCM->{$_};
        }
        
        $stat[3] = sum( values( %{$UCM} ) ) || 0;

        $stat[5] = max( @cms ) || 0;
        $stat[6] = sprintf( "%.1f", mean( @cms ) || 0 );
        $stat[7] = median( @cms ) || 0;

        my @pw = values( %{$TEXT} );
        $stat[4] = sum( @pw ) || 0;
        $stat[8] = sprintf( "%.1f", mean( @pw ) || 0 );
        $stat[9] = median( @pw ) || 0;
        
        close FP;
    }

    if ( $stat[0] ) {
        open FP, ">>lj.stat.csv";
        my $out_line = join( "\t", $uc, $uname, @stat )."\n";
        $out_line =~ s/\./,/g;
        print FP $out_line;
        close FP;    
    }
    
    print "$uname, $c_ok, $c_total                \r";
}
print "$c_ok, $c_total                \n";

open FP, ">lj.cm.csv";
foreach ( sort { $CM->{$b} <=> $CM->{$a} } keys( %{$CM} )   ) {
    print FP $_, "\t", $CM->{$_}, "\n";
}
close FP;

open FP, ">lj.cmout.csv";
foreach ( sort { $CMOUT->{$b} <=> $CMOUT->{$a} } keys( %{$CMOUT} )   ) {
    print FP $_, "\t", $CMOUT->{$_}, "\n";
}
close FP;

print "DONE\n";

