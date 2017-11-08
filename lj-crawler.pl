use warnings;
use strict;
use utf8;
use threads;
use threads::shared;
use Thread::Queue;
use JSON;

#--------------------------------------------------------------------------------------------
# LJ Crawler 0.9.3, Roman Lugovkin (c) 2017
#--------------------------------------------------------------------------------------------
# Настоящее ПО написано в исследовательских целях. 
# Используя данное ПО вы принимаете на себя ответственность за возможное нарушение 
# лицензионного соглашения сервиса www.livejournal.com
# Оригинальный код: https://github.com/roman-lugovkin/lj-crawler/
#--------------------------------------------------------------------------------------------

$| = 1;

my $THREADS = 5;
my $AT :shared;
my $COUNTER :shared;

#--------------------------------------------------------------------------------------------
# Запуск по умолчанию парсит журналы (контент постов и комментарии) из входного файла по текущему месяцу
# lj-crawler.pl lj-top.json
# Обрабатываем только 1000 журналов из списка
# lj-crawler.pl lj-top.json -t 1000
# Парсим три первых месяца 2007 года, список берем из lj.list
# lj-crawler.pl lj.list -y 2007 -m 1-3
# Парсим три первых месяца 2007 года, список берем из lj.list
# lj-crawler.pl lj.list -y 2007-2009
#--------------------------------------------------------------------------------------------

# Можно json из парсера топа или просто текстовый файл с перечнем юзеров
my $IN = shift @ARGV || 'lj-top.json';
my %OP = @ARGV;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$mon ++;
$year += 1900;

my $YEAR    = $OP{'-y'} || $year; 
my $MONTH   = $OP{'-m'} || $mon; 
my $CM      = $OP{'-cm'} || 'y'; 
my $HR      = $OP{'-h'} || 'y'; 
my $DROP    = $OP{'-d'} || 0; 
my $GET_TOP = $OP{'-t'} || 0; 
my $DATA    = $OP{'-data'} || './data'; 

exit unless ( -e $IN );

my $queue = Thread::Queue->new;

print "Loading queue... ";
open FP, "<$IN";

my @window = ( 0, 1000000000 );
if ( $GET_TOP ) {
    my @ww = split( '-', $GET_TOP );
    if ( scalar(@ww) == 1 ) {
        $window[1] = $ww[0];
    }
    else {
        $window[0] = $ww[0] || $window[0];
        $window[1] = $ww[1] || $window[1];
    }
}

my $qc = 1;
while ( <FP> ) {
    s/(\n|\r)//gsm;
    my $user;
    eval {
        $user = from_json( $_ );
    };
    $user = {} unless ( defined $user );
    my $name = $user->{'user_name'} || $_ || ''; # Если вдруг этого поля нет, то мы пытаемся загрузить просто текстовый файл
    $name =~ s/_/\-/g;
    if ( $name ) {
        if ( ( $qc >= $window[0] ) and ( $qc <= $window[1] ) ) {
            $queue->enqueue( $name );
        }

        $qc ++;
        if ( $qc > $window[1] ) {
            last;
        }
    };
}
close FP;
print $queue->pending, " Loaded\n";

print "RUNNING THREADS...";

my @threads;
foreach ( 1..$THREADS ) {
    $AT ++;
    push @threads, threads->create( \&get_user, $_ );
}

print "OK\n";

foreach ( @threads ) {
    $_->join();
}

print "FINISH $AT\n";

exit;

sub get_user(@) {
    my $process = shift || 0;

    while ( defined( my $user = $queue->dequeue_nb ) ) {
        $COUNTER++;
        print "$process $COUNTER $user\n";
        `perl lj-user-crawler.pl $user -y $YEAR -m $MONTH -c $COUNTER -h $HR -cm $CM -d $DROP -data $DATA > $process.lj.log`;
        if ( -e 'lj.403.lock' ) {
            print "IP blocked on $COUNTER journal with name $user. Try to use another IP\n";
            last;
        }
    }
    
    $AT --;
}
