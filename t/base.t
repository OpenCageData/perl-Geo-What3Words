use strict;
use HTTP::Tiny;
use Test::More;
use Test::Exception;
use Test::Warn;
use Data::Dumper;
use Encode     ();
use List::Util qw(first);

use utf8; # this file is written in utf8
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# nicer output for diag and failures, see
# http://perldoc.perl.org/Test/More.html#CAVEATS-and-NOTES
my $builder = Test::More->builder;
binmode $builder->output,         ":encoding(UTF-8)";
binmode $builder->failure_output, ":encoding(UTF-8)";
binmode $builder->todo_output,    ":encoding(UTF-8)";

## Make sure verbose messages go to the test output instead of STDOUT
## And with 'note' instead of 'diag' the output of test summaries stays
## clean
my $logging_callback = sub {
    my $message = shift;
    note $message;
};

## to run tests with an W3W API key
## PERLLIB=./lib W3W_API_KEY=<your key> perl t/base.t
##
my $api_key = $ENV{W3W_API_KEY} || 'randomteststring';
my $ua      = HTTP::Tiny->new();

use Geo::What3Words;

## Missing API key
##
dies_ok {
    Geo::What3Words->new(logging => $logging_callback);
}
'dies when missing key';

## These methods don't access the HTTP API
##
{
    my $w3w = Geo::What3Words->new(key => $api_key, ua => $ua, logging => $logging_callback);
    is($w3w->valid_words_format('abc.def.ghi'),     1, 'valid_words_format - valid');
    is($w3w->valid_words_format('abcdef.ghi'),      0, 'valid_words_format - only two');
    is($w3w->valid_words_format('abc.def.ghi.jkl'), 0, 'valid_words_format - too many');
    is($w3w->valid_words_format('Abc.def.ghi'),     0, 'valid_words_format - not all lowercase');
    is($w3w->valid_words_format(''),                0, 'valid_words_format - empty');
    is($w3w->valid_words_format(),                  0, 'valid_words_format - undef');

    is($w3w->valid_words_format('meyal.şifalı.döşeme'), 1, 'valid_words_format - valid Turkish utf8');
    is($w3w->valid_words_format('диета.новшество.компаньон'),
        1, 'valid_words_format - valid Russian utf8');
    is($w3w->valid_words_format('Mосква.def.ghi'), 0, 'valid_words_format - not all lowercase utf8');
}

## Net::Ping is only loaded when calling ping()
##
ok(!exists($INC{'Net/Ping.pm'}), 'Net::Ping not loaded on startup');

## Fake user agent, records requested URLs and returns a canned response
##
{

    package FakeUA;
    sub new   { my ($class, $content) = @_; return bless {content => $content, urls => []}, $class }
    sub agent { }

    sub get {
        my ($self, $url) = @_;
        push @{$self->{urls}}, $url;
        return {success => 1, status => 200, content => $self->{content}};
    }
}

## Request building and response decoding, no HTTP API access
##
{
    ## raw UTF-8 bytes, like HTTP::Tiny returns them
    my $content
        = '{"words":"' . Encode::encode_utf8('диета.новшество.компаньон') . '","language":"ru"}';
    my $fake_ua = FakeUA->new($content);
    my $w3w     = Geo::What3Words->new(key => 'abc', ua => $fake_ua, logging => $logging_callback);

    is( $w3w->pos2words('51.484463,-0.195405', 'ru'),
        'диета.новшество.компаньон',
        'pos2words - decodes utf8'
    );
    is( $fake_ua->{urls}->[0],
        'https://api.what3words.com/v3/convert-to-3wa?coordinates=51.484463%2C-0.195405&format=json&key=abc&language=ru',
        'pos2words - request url'
    );

    $w3w->position_to_words('51.484463,-0.195405');
    unlike($fake_ua->{urls}->[1], qr/language/, 'position_to_words - no language parameter if not set');

    $w3w->words_to_position('prom.cape.pump');
    like(
        $fake_ua->{urls}->[2],
        qr{/convert-to-coordinates\?format=json&key=abc&words=prom\.cape\.pump$},
        'words_to_position - request url'
    );

    $w3w->words_to_position('///Index.Home.Raft');
    is(scalar(@{$fake_ua->{urls}}), 4, 'words_to_position - lenient check passes on input valid_words_format rejects');
}

## Invalid input is rejected without calling the HTTP API
##
{
    my $fake_ua = FakeUA->new('{}');
    my $w3w     = Geo::What3Words->new(key => 'abc', ua => $fake_ua, logging => $logging_callback);

    foreach my $words (undef, '', 'abc.def', 'abc.def.ghi.jkl', 'abc..ghi', 'abc def.ghi.jkl') {
        my $label = defined($words) ? "'$words'" : 'undef';
        warning_like {
            is($w3w->words_to_position($words), undef, "words_to_position - invalid $label");
        }
        qr/invalid 3 word address/, "words_to_position - warning for $label";
    }

    foreach my $position (undef, '', 'invalid,coords', '1', '1,2,3', '91,0', '0,181', '-90.1,0') {
        my $label = defined($position) ? "'$position'" : 'undef';
        warning_like {
            is($w3w->pos2words($position), undef, "pos2words - invalid $label");
        }
        qr/invalid coordinates/, "pos2words - warning for $label";
    }

    is(scalar(@{$fake_ua->{urls}}), 0, 'invalid input - no API requests');

    ## valid edge cases still reach the API
    $w3w->position_to_words($_) for ('90,180', '-90,-180', ' 1.5 , -.5 ', '+1,2.');
    is(scalar(@{$fake_ua->{urls}}), 4, 'position_to_words - valid edge cases call the API');
}

## Host extraction for ping()
##
is(Geo::What3Words::_host_from_url('https://api.what3words.com/v3/'), 'api.what3words.com', '_host_from_url - host');
is(Geo::What3Words::_host_from_url('http://user:pw@127.0.0.1:8080/v3/'),
    '127.0.0.1', '_host_from_url - ip, port and userinfo');
is(Geo::What3Words::_host_from_url('http://[::1]:8080/v3/'), '::1', '_host_from_url - ipv6');
is(Geo::What3Words::_host_from_url('not a url'),             undef, '_host_from_url - invalid');


## Invalid API key
##
warning_like {
    my $w3w = Geo::What3Words->new(key => 'rubbish-key', ua => $ua, logging => $logging_callback);
    is($w3w->pos2words('1,2'), undef, 'invalid key');
}
qr/401/, 'got 401 warning';


my $w3w = Geo::What3Words->new(key => $api_key, ua => $ua, logging => $logging_callback);
isa_ok($w3w, 'Geo::What3Words');

if ($api_key eq 'randomteststring') {
    note "Set W3W_API_KEY environment variable to run rest of tests";
    done_testing();
    exit;
}


##
## POS2WORDS, WORDS2POS
##

{
    my $words = $w3w->pos2words('51.484463,-0.195405');
    ok($w3w->valid_words_format($words), 'pos2words');

    my $pos = $w3w->words2pos($words);
    like($pos, qr/^51.\d+,-0.19\d+$/, 'words2pos');


    is($w3w->pos2words('invalid,coords'), undef, 'pos2words - invalid input');
    is($w3w->words2pos('does.not.exist'), undef, 'words2pos - invalid input');

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
    #print STDERR Dumper $res;
    is($res->{language}, 'en', 'position_to_words - language');
    is_deeply([$res->{coordinates}->{lat}, $res->{coordinates}->{lng}], [$lat, $lng], 'position_to_words - position');

    $three_words_string = $res->{words};
    ok($w3w->valid_words_format($three_words_string), 'position_to_words - got 3 words');

    ## now Russian, питомец.шутить.намеренно
    my $res_ru = $w3w->position_to_words($lat . ',' . $lng, 'ru');
    $three_words_string_russian = $res_ru->{words};

    isnt($three_words_string, $three_words_string_russian, 'position_to_words - english vs russian');
}


##
## WORDS_TO_POSITION
##
{
    my $res = $w3w->words_to_position($three_words_string);
    #print STDERR Dumper $res;

    is($res->{language}, 'en', 'words_to_position - language');
    is_deeply([$res->{coordinates}->{lat}, $res->{coordinates}->{lng}], [$lat, $lng], 'words_to_position - position');
    is($res->{words}, $three_words_string, 'words_to_position - words');
}


##
## GET_LANGUAGES
##
{
    my $res = $w3w->get_languages();

    ok(scalar(@{$res->{languages}}) > 1, 'get_languages - at least one');

    my $rh_lang = first { $_->{'code'} eq 'ru' } @{$res->{languages}};
    like($rh_lang->{name},       qr/^Russian/,        'get_languages - name');
    like($rh_lang->{nativeName}, qr/^Русский/, 'get_languages - name encoded in utf8');
}


done_testing();
1;
