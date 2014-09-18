use strict;
use Test::More tests => 28;
use Test::Exception;
use Data::Dumper;
use List::Util qw(first);
use Test::LWP::Recorder;

use utf8; # this file is written in utf8
binmode STDOUT, ':utf8'; 
binmode STDERR, ':utf8';

# nicer output for diag and failures, see
# http://perldoc.perl.org/Test/More.html#CAVEATS-and-NOTES
my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";


use_ok('Geo::What3Words');




## Make sure verbose messages go to the test output instead of STDOUT
## And with 'note' instead of 'diag' the output of test summaries stays
## clean
my $logging_callback = sub {
  my $message = shift;
  note $message;
};


## Instead of live HTTP requests we recorded the responses. To re-record
## them set these two variables, e.g. 
## PERLLIB=./lib W3W_RECORD_REQUESTS=1 W3W_API_KEY=<your key> perl t/base.t
##
my $w3w_record = $ENV{W3W_RECORD_REQUESTS} ? 1 : 0;
my $api_key    = $ENV{W3W_API_KEY} || 'randomteststring';

my $ua = Test::LWP::Recorder->new({
    record => $w3w_record,
    cache_dir => 't/LWPCache', 
    filter_params => [qw(key)],
    filter_header => [qw(Client-Peer Expires Client-Date Cache-Control)],
});



## Missing of invalid keys
##
dies_ok {
  Geo::What3Words->new( logging => $logging_callback);
} 'missing key';

{
  my $w3w = Geo::What3Words->new( key => 'rubbish-key', ua => $ua, logging => $logging_callback );
  is( $w3w->pos2words('1,2'), undef, 'invalid key');
}





my $w3w = Geo::What3Words->new( key => $api_key, ua => $ua, logging => $logging_callback );
isa_ok($w3w, 'Geo::What3Words');



## These methods don't access the HTTP API
##
{

  is( $w3w->valid_words('abc.def.ghi'),     3, 'valid_words - valid' );
  is( $w3w->valid_words('abcdef.ghi'),      0, 'valid_words - only two' );
  is( $w3w->valid_words('abc.def.ghi.jkl'), 0, 'valid_words - too many' );
  is( $w3w->valid_words('Abc.def.ghi'),     0, 'valid_words - not all lowercase' );
  is( $w3w->valid_words(''),                0, 'valid_words - empty' );
  is( $w3w->valid_words(),                  0, 'valid_words - undef' );

  is( $w3w->valid_words('meyal.şifalı.döşeme'),   3, 'valid_words - valid Turkish utf8' );
  is( $w3w->valid_words('диета.новшество.компаньон'),   3, 'valid_words - valid Russian utf8' );
  is( $w3w->valid_words('Mосква.def.ghi'),  0, 'valid_words - not all lowercase utf8' );

  is( $w3w->valid_words('*exampleword'),    1, 'valid_words - OneWord' );


}




##
## GET_LANGUAGES
##
{
  my $res = $w3w->get_languages();


  ## just in case the hardcoded key gets blocked 
  if ( $res && ref($res) eq 'HASH' && exists($res->{error}) && $res->{error} eq 'X1' ){
    skip 'API key is invalid', 15;
  }


  ok( scalar(@{$res->{languages}}) > 1, 'get_languages - at least one');

  my $ru = first { $_->{'code'} eq 'ru'} @{$res->{languages}};
  is($ru->{name_display}, 'Русский', 'get_languages - name encoding in utf8');
}



##
## POS2WORDS, WORDS2POS
##

{
  my $words = $w3w->pos2words('51.484463,-0.195405');
  like($words, qr/^(\w+)\.(\w+)\.(\w+)$/, 'pos2words');

  my $pos = $w3w->words2pos($words);
  like($pos, qr/^51.\d+,-0.19\d+$/, 'words2pos');

  $pos = $w3w->words2pos('*libertytech');
  like($pos, qr/^51.\d+,-0.1\d+$/, 'words2pos');

}


##
## POSITION_TO_WORDS
##

my $lat = 51.484463;
my $lng = -0.195405;
my $three_words_string;
my $three_words_string_russian;

{
  my $res = $w3w->position_to_words($lat . ',' . $lng);



  is($res->{language}, 'en', 'words_to_position - language');
  is_deeply(
    $res->{position},
    [ $lat, $lng ],
    'words_to_position - position'
  );
  is( scalar( @{$res->{words}}), 3, 'words_to_position - got 3 words');

  $three_words_string = join('.', @{$res->{words}} );



  ## now Russian
  my $res_ru = $w3w->position_to_words($lat . ',' . $lng, 'ru');
  $three_words_string_russian = join('.', @{$res_ru->{words}} );
  isnt(
    $three_words_string,
    $three_words_string_russian,
    'words_to_position - en vs russian'
  );

}


##
## WORDS_TO_POSITION
##
{
  my $res = $w3w->words_to_position($three_words_string);



  is($res->{language}, 'en', 'position_to_words - language');
  is_deeply(
    $res->{position},
    [ $lat, $lng ],
    'position_to_words - position'
  );
  is($res->{type}, '3 words', 'position_to_words - type');
  is_deeply(
    $res->{words},
    [ split('\.', $three_words_string) ],
    'position_to_words - words'
  );


}




##
## ONEWORD_AVAILABLE
##
{
    my $res = $w3w->oneword_available('*TestingThePerlModule');
    ok($res->{available}, 'oneword_available: TestingThePerlModule');
}


