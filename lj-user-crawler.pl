use warnings;
use strict;
use utf8;
use LWP;
use Encode;
use JSON;
use List::Util qw/max/;
use HTTP::Cookies;

$| = 1;

no warnings 'utf8';

#--------------------------------------------------------------------------------------------
# LJ Crawler 0.9.3, Roman Lugovkin (c) 2017
#--------------------------------------------------------------------------------------------
# Настоящее ПО написано в исследовательских целях. 
# Используя данное ПО вы принимаете на себя ответственность за возможное нарушение 
# лицензионного соглашения сервиса www.livejournal.com
# Оригинальный код: https://github.com/roman-lugovkin/lj-crawler/
#--------------------------------------------------------------------------------------------

#--------------------------------------------------------------------------------------------
# По умолчанию: парсим журнал за текущий месяц
# lj-user-crawler.pl tema
# Парсим три первых месяца 2007 года журнала tema
# lj-user-crawler.pl tema -y 2007 -m 1-3
# Парсим журнал tema с 2007 по 2009 года
# lj-user-crawler.pl tema -y 2007-2009
#--------------------------------------------------------------------------------------------

sub process_user(@);
sub process_post(@);
sub get_page(@);

my $ua = LWP::UserAgent->new();
my $cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie( 0, 'adult_explicit', 1, "/", ".livejournal.com" );
$cookie_jar->set_cookie( 0, 'prop_opt_readability', 1, "/", ".livejournal.com" );
$ua->cookie_jar( $cookie_jar );

my $TARGET = shift || '';  # Целевой журнал
my %OP = @ARGV;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$mon ++;
$year += 1900;

my $YEAR    = $OP{'-y'} || $year;    # Год(ы)
my $MONTH   = $OP{'-m'} || $mon;    # Месяц(ы) если год указан только один
my $CM      = $OP{'-cm'} || 'y';    # С комментариями (y/n)?
my $HR      = $OP{'-h'} || 'y';    # С сылками (y/n)?
my $COUNTER = $OP{'-c'} || 1;    # Счетчик (служебный)
my $DROP    = $OP{'-d'} || 0;     # Дропнуть файлы данных пользователя перед парсингом
my $DATA    = $OP{'-data'} || './data'; # Каталог данных

exit unless ( $TARGET );

unless ( -d $DATA ) {
    mkdir $DATA;
}

$CM = '' unless ( $CM eq 'y' );
$HR = '' unless ( $HR eq 'y' );

# Сформируем глобальные параметры диапазонов
my @YEARS;
if ( $YEAR =~ /^(\d\d\d\d)-(\d\d\d\d)$/ ) {
    foreach ( $1..$2 ) {
        push @YEARS, $_;
    }
}
else {
    push @YEARS, $YEAR;
}

my @MONTHS;
my @mns = split( '-', $MONTH );
@mns = ( 1, 12 ) if ( !@mns or ( scalar(@YEARS) > 1 ) );
push @mns, $mns[0] if ( scalar(@mns) == 1 );
foreach ( $mns[0]..$mns[1] ) {
    push @MONTHS, sprintf("%02d", $_);
}

# Удаляем файлы данных?
if ( $DROP ) {
    unlink "$DATA/commentators.$TARGET.csv";
    unlink "$DATA/cm.$TARGET.json";
    unlink "$DATA/content.$TARGET.csv";
    unlink "$DATA/href.$TARGET.csv";
}

# Поехали
process_user( $TARGET, $COUNTER );

exit;

sub process_user(@) {
    my $target_user = shift;
    my $user_cnt = shift || 1;

    my @links;
    my @stat;
    
    # Формируем базовый URL журнала
    my $base_url = '';
    my $base_re = '';
    if ( $target_user =~ /^\-/ ) {
        $base_url = "https://users.livejournal.com/$target_user/";
    }
    else {
        $base_url = "https://$target_user.livejournal.com/";
    }
    
    if ( $target_user eq 'zyalt' ) {
        # Чтоб его...
        $base_url = "https://varlamov.ru/";
    }

    print "USER: $target_user\n";
    print "Looking for posts...\n";
    
    # Собираем ссылки на посты по месяцам
    foreach my $year ( @YEARS ) {
        foreach my $month ( @MONTHS ) {
            my $cpage = $base_url.$year.'/'.$month.'/';
            my $chtml = get_page( $cpage );
            while ( $chtml =~ /href="($base_url(\d+?)\.html)"/gsm ) {
                my $page_url = $1;
                my $page_id = $2;
                push @links, [ $page_url, $year, $month ];
                print $page_id, "\n";
            }
        }
    }
    
    print scalar(@links), " posts for processing\n";

    # Процессим посты собирая статистику комментаторов сразу
    my $total_posts = scalar(@links);
    my $t1 = time();
    my $commentators = {};
    my $post_cnt = 1;
    foreach ( @links ) {
        my ( $u, $s ) = process_post( $target_user, $_, qq{$user_cnt/$target_user/$post_cnt/$total_posts} );
        $post_cnt ++;
        foreach ( keys(%{$u}) ) {
            $commentators->{$_} += $u->{$_};
        }
        push @stat, $s;
    }
    my $t2 = time();

    # Выводим статистику комментаторов по журналу в отдельный файл, если надо
    if ( $CM ) {
        if ( %{$commentators} ) {
            open FP, ">$DATA/commentators.$target_user.csv";
            foreach ( sort { $commentators->{$b} <=> $commentators->{$a} } keys( %{$commentators} )   ) {
                print FP $_, "\t", $commentators->{$_}, "\n";
            }
            close FP;
        }
    }

    print "STAT:\n";
    my $r = 0;
    my $c = 0;
    foreach ( @stat ) {
        $r += $_->[1] || 0;
        $c += $_->[2] || 0;
        print join( "\t", @{$_} ), "\n";
    }
    print "TOTAL: ", $r, " ", $c, "\n";
    print "TIME: ", $t2 - $t1, "\n";
}

sub process_post(@) {
    my $target_user = shift;
    my $href_data = shift || [];
    my $info = shift || '';
    my $post_id;
    
    my $href = $href_data->[0];
    my $year = $href_data->[1];
    my $month = $href_data->[2];
    
    if ( $href =~ /\/(\d+)\.html/  ) {
        $post_id = $1;
    }

    return ( {}, [] ) unless $post_id;
    
    my $users = {};
    my $next = 1;
    print "$info POST URL $href\n";
    my $rpl = 0;
    my $cm = 0;
    my $last_talk_id = 0;

    # Берем базовый пост
    my $html = get_page( "$href?page=$next&format=light" );
    $html =~ s/(\r|\n)//gsm;
    $cookie_jar->save;

    # Страницы
    my @pages;
    while ( $html =~ /href="\/$post_id\.html\?format=light&page=(\d+)"/g ) {
        push @pages, $1;
    }

    # Флаг нового редактора и разметки
    my $new_editor = 0;    

    # Еще раз проверим время, вдруг криво напарсили список и туда попало лишнее
    my $post_time = '';
    if ( $html =~ /<time[^>]*?>(.+?)<\/time>/ ) {
        $post_time = $1;
        $post_time =~ s/<[^>]+?>//gsm;
        
        # Если новый формат - преобразуем к старому
        if ( $post_time =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)$/ ) {
            $post_time = $3.'-'.$1.'-'.$2;
            $new_editor = 1;
            # и еще время
            if ( $html =~ /<time>(\d\d)\:(\d\d)<\/time>/ ) {
                $post_time .= ' '.$1.':'.$2.':00';
            }
        }
        
        print "[$post_time]\n";
        unless ( $post_time =~ /^$year\-$month\-/) {
            return ( {}, [] );
        }
    }

    my $data;
    my @comments;

    # Комvентарии первой страницы уже на странице в виде JS-объекта - вырезаем их и парсим
    if ( $html =~ /Site\.page = \{(.+?)\};/ ) {
        my $js = '{'.$1.'}';
        eval {
            $data = from_json( $js );
        };
            
        if ( $data ) {
            my $cms = $data->{'comments'} || [];
            my $cm_on_page = scalar( @{$cms} );
            $cm += $cm_on_page;
            $rpl = $data->{'replycount'} || 0 unless ( $rpl );
            print "RPL: ", $data->{'replycount'} || 0, "\n";
            print "COMMENTS: ", $cm_on_page, "\n";
                
            foreach ( @{$data->{'comments'}} ) {
                delete $_->{'actions'};
                delete $_->{'thread_url'};
                delete $_->{'lj_statprefix'};
                my $dc;
                eval {
                    $dc = to_json( $_ );
                };
                push @comments, $_ if ( $dc );
                if ( $_->{'uname'} ) {
                    $users->{ $_->{'uname'} } ++;
                }
            }
        }
    }

    # Выдираем тайтл и контент поста
    my $title = '';
    if ( $html =~ /<h1[^>]+?>(.+?)<\/h1>/ ) {
        $title = $1;
        $title =~ s/<[^>]+?>//gsm;
        $title =~ s/\t/ /gsm;
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
    }
    
    my $body = '';
    my @hrefs;
    if ( $html =~ /<article class="\s?b\-singlepost\-body[^>]+?>(.+?)<\/article>/ ) {
        $body = $1;
    }
    elsif ( $html =~ /<div class="aentry\-post__content">(.+?)<div class=" aentry\-post__slot/ ) {
        $body = $1;
        $body .= '</div>';
    }

    # Теги
    my @tags;
    while ( $html =~ /<meta property="article:tag" content="([^"]+?)"\/>/gsm ) {
        push @tags, $1;
    }

    if ( $body ) {
        # Ссылки в отдельный файл - может пригодится
        while ( $body =~ /href="(.+?)"/g ) {
            push @hrefs, $1;
        }
        
        # Удаляем разметку (этого можно не делать если надо сохранить ссылки на фотографии)
        $body =~ s/<[^>]+?>/ /gsm;
        
        # В строку
        $body =~ s/(\r|\n)/ /gsm;
        $body =~ s/\s+/ /gsm;
        $body =~ s/\t/ /gsm;
    }
    
    # Пишем контент
    open FP, ">>$DATA/content.$target_user.csv";
    print FP join( "\t", $target_user, $post_id, $post_time, $title, $body, $rpl, join(", ", @tags) ), "\n";
    close FP;

    if ( $HR ) {
        # Пишем ссылки, если вдруг надо
        open FP, ">>$DATA/href.$target_user.csv";
        print FP join( "\t", $target_user, $post_id, $post_time, @hrefs ), "\n";
        close FP;
    }

    # Собираем коментарии постранично если заявленное число не равно собранному
    if ( $CM and ( $rpl != $cm ) ) {
        # Определяем сколько страниц
        my $last_page = 1;
        $last_page = max @pages if ( @pages );
        $cm = 0;
        $users = {};
        
        # Поехали
        foreach $next ( 1..$last_page ) {
            print "PAGE $next\n";
            # Хитрый вызов неофициального RPC
            my $json = get_page( "https://www.livejournal.com/__rpc_get_thread?journal=$target_user&itemid=$post_id&flat=&media=&expand_all=1&page=".$next );
            $data = undef;
            
            # Возвращается JSON-объект, сразу парсим его
            eval {
                $data = from_json( $json );
            };

            if ( $data ) {
                my $cms = $data->{'comments'} || [];
                my $cm_on_page = scalar( @{$cms} );
                $cm += $cm_on_page;
                $rpl = $data->{'replycount'};
                print "RPL: ", $data->{'replycount'}, "\n";
                print "COMMENTS: ", $cm_on_page, "\n";
                
                # Идем по комментариям и удаляем лишнее собирая статистику комментаторов
                foreach ( @{$data->{'comments'}} ) {
                    # Немного постим лишние поля комментариев
                    delete $_->{'actions'};
                    delete $_->{'thread_url'};
                    delete $_->{'lj_statprefix'};
                    
                    # Проверка на корректность utf
                    my $dc;
                    eval {
                        $dc = to_json( $_ );
                    };
                    push @comments, $_ if ( $dc );

                    if ( $_->{'uname'} ) {
                        $users->{ $_->{'uname'} } ++;
                    }
                }
            }
        }
    }
    
    # Пишем комментарии
    if ( $CM ) {
        open FP, ">>$DATA/cm.$target_user.json";
        print FP join("\t", $target_user, $post_id, $post_time, $rpl, $cm, to_json( \@comments, { pretty => 0 } ) ), "\n";
        close FP;
    }

    print "RPL/CM: $rpl/$cm\n";
    return ( $users, [ $href, $rpl, $cm ], \@tags );
}

exit;

sub get_page(@) {
    my $url = shift;
    my $page_num = shift || 0;
    
    my $html = '';
    my $r = $ua->get( $url );
    if ( $r->is_success ) {
        $html = decode( 'utf8', $r->content );
        if ( -d "./cache" ) {
            open FP, ">./cache/last-$TARGET.html";
            print FP $html;
            close FP
        }
    }
    else {
        print "ERROR: ", $r->status_line, "\n";
        #exit;
    }
    
    return $html;
}