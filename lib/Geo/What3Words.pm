# ABSTRACT: Turn WGS84 coordinates into three words or OneWords and vice-versa using w3w.co HTTP API

package Geo::What3Words;

use strict;
use warnings;
use URI;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Net::Ping;
use Net::Ping::External;

=head1 DESCRIPTION

what3words (http://what3words.com/) divides the world into 57 trillion squares of 3 metres x 3 metres.
Each square has been given a 3 word address comprised of 3 words from the dictionary.

This module calls their API (http://what3words.com/api/reference) to convert coordinates into
those 3 word addresses and back.

You need to sign up at http://what3words.com/login and then register for an API key
at http://what3words.com/api/signup”



=head1 SYNOPSIS

  my $w3w = Geo::What3Words->new();

  $w3w->pos2words('51.484463,-0.195405');
  # returns 'three.example.words'

  $w3w->pos2words('51.484463,-0.195405', 'ru');
  # returns 'три.пример.слова'

  $w3w->words2pos('three.example.words');
  # returns '51.484463,-0.195405' (latitude,longitude)

  $w3w->words2pos('*libertytech');
  # returns '51.512573,-0.144879'


=cut






=method new

Creates a new instance. The api key is required.

  my $w3w = Geo::What3Words->new( key => 'your-api-key' );
  my $w3w = Geo::What3Words->new( key => 'your-api-key', language => 'ru' );

For debugging you can either set logging or provide a callback.

  my $w3w = Geo::What3Words->new( key => 'your-api-key', logging => 1 );
  # will print debugging output to STDOUT

  my $callback = sub { my $msg = shift; $my_log4perl_logger->info($msg) };
  my $w3w = Geo::What3Words->new( key => 'your-api-key', logging => $callback );
  # will log with log4perl.

=cut


sub new {
  my ($class, %params) = @_;

  my $self = {};
  $self->{api_endpoint}     = $params{api_endpoint} || 'http://api.what3words.com/';
  $self->{key}              = $params{key}      || die "API key not set";
  $self->{language}         = $params{language};
  $self->{logging}          = $params{logging};

  ## _ua is used for testing. But could also be used to
  ## set proxies or such
  $self->{ua} = $params{ua} || LWP::UserAgent->new;

  my $version  = $Geo::What3Words::VERSION || '';
  $self->{ua}->agent("Perl Geo::What3Words $version");

  return bless($self,$class);
}






=method ping

Check if the remote server is available. This is helpful for debugging or
testing, but too slow to run for every conversion.

  $w3w->ping();

=cut

sub ping {
  my $self = shift;

  ## http://example.com/some/path => example.com
  ## also works with IP addresses
  my $host = URI->new($self->{api_endpoint})->host;

  $self->_log("pinging $host...");

  my $netping = Net::Ping->new('external');
  my $res = $netping->ping($host);

  $self->_log($res ? 'available' : 'unavailable');

  return $res;
}







=method words2pos

Tiny wrapper around words_to_position.

  $w3w->words2pos('three.example.words');
  # returns '51.484463,-0.195405' (latitude,longitude)

  $w3w->words2pos('*libertytech');
  # returns '51.512573,-0.144879'

=cut

sub words2pos {
  my ($self, @params) = @_;
  my $res = $self->words_to_position(@params);

  if ( $res && ref($res) eq 'HASH' && exists($res->{position}) ){
    return $res->{position}->[0] . ',' . $res->{position}->[1];
  }
  return;
}







=method pos2words

Tiny wrapper around position_to_words.

  $w3w->pos2words('51.484463,-0.195405'); # latitude,longitude
  # returns 'three.example.words'

  $w3w->pos2words('51.484463,-0.195405', 'ru');
  # returns 'три.пример.слова'

=cut

sub pos2words {
  my ($self, @params) = @_;
  my $res = $self->position_to_words(@params);

  if ( $res && ref($res) eq 'HASH' && exists($res->{words}) ){
    return join('.', @{$res->{words}} );
  }
  return;
}








=method valid_words

Returns 3 if the string looks like three words, 1 if it looks like a OneWord.
Returns 0 otherwise.

  $w3w->valid_words('one.two.three');
  # returns 3

  $w3w->valid_words('*one-two12');
  # return 1

=cut

sub valid_words {
  my $self = shift;
  my $words = shift;

  ## Translating the PHP regular expression w3w uses in their
  ## documentation
  ## http://perldoc.perl.org/perlunicode.html#Unicode-Character-Properties
  ## http://php.net/manual/en/reference.pcre.pattern.differences.php
  return 0 unless $words;


  return 3 if ($words =~ m/^(\p{Lower}+)\.(\p{Lower}+)\.(\p{Lower}+)$/ );
  return 1 if ($words =~ m/^\*[\p{Lower}\-0-9]{6,31}$/ );
  return 0;
}








=method words_to_position

Returns a more verbose response than words2pos.

  $w3w->words_to_position('prom.cape.pump');
  #   {
  #      'language' => 'en',
  #      'position' => [
  #                      '51.484463',
  #                      '-0.195405'
  #                    ],
  #      'type' => '3 words',
  #      'words' => [
  #                   'prom',
  #                   'cape',
  #                   'pump'
  #                 ]
  #   },

=cut

sub words_to_position {
  my $self = shift;
  my $words = shift;
  my $language = shift || $self->{language};

  return $self->_execute_query('w3w', {string => $words, lang => $language });
}










=method position_to_words

Returns a more verbose response than pos2words.

  $w3w->position_to_words('51.484463,-0.195405')
  # {
  #    'language' => 'en',
  #    'position' => [
  #                    '51.484463',
  #                    '-0.195405'
  #                  ],
  #    'words' => [
  #                 'prom',
  #                 'cape',
  #                 'pump'
  #               ]
  # }

=cut

sub position_to_words {
  my $self = shift;
  my $position = shift;
  my $language = shift || $self->{language};

  return $self->_execute_query('position', {position => $position, lang => $language });
}









=method get_languages

Retuns a list of language codes and names.

  $w3w->get_languages();
  # {
  #     'languages' => [
  #                      {
  #                        'name_display' => 'Deutsch',
  #                        'code' => 'de'
  #                      },
  #                      {
  #                        'name_display' => 'English',
  #                        'code' => 'en'
  #                      },
  #                      {
  #                        'name_display' => "Español",
  #                        'code' => 'es'
  #                      },
  # ...

=cut

sub get_languages {
  my $self = shift;
  my $position = shift;

  return $self->_execute_query('get-languages');
}










=method oneword_available

Checks if a OneWord is available

  $w3w->oneword_available('helloworld');
  # {
  #   'message' => 'Your OneWord is available',
  #   'available' => 1
  # }

=cut

sub oneword_available {
  my $self = shift;
  my $word = shift;
  my $language = shift || $self->{language};

  return $self->_execute_query('oneword-available', {word => $word, lang => $language });
}













sub _execute_query {
  my $self        = shift;
  my $method_name = shift;
  my $rh_params   = shift || {};


  my $url = URI->new($self->{api_endpoint} . $method_name);

  my $rh_fields = {
      key    => $self->{key},
      %$rh_params
  };
  delete $rh_fields->{lang} if !$rh_fields->{lang};


  local $Data::Dumper::Indent = 0;
  $self->_log("POST " . $url . ' fields: ' . Dumper $rh_fields);
  my $response = $self->{ua}->post($url, $rh_fields);

  if ( ! $response->is_success) {
    warn "got no response from $url";
    $self->_log("got no response from $url");
    return;
  }

  my $json = $response->decoded_content;
  $self->_log($json);

  return decode_json($json);
}


sub _log {
  my $self    = shift;
  my $message = shift;
  return unless $self->{logging};

  if ( ref($self->{logging}) eq 'CODE' ){
    my $lc = $self->{logging};
    &$lc("Geo::What3Words -- " . $message);
  } 
  else {
    print "Geo::What3Words -- " . $message . "\n";
  }
  return
}

# convert '$lat,$lng', [$lat,$lng], {lat=>$lat,lng=>$lng} to
# a string.
# sub _position_to_string {
#   my $value = shift;
#   if ( my $type = ref($value) ){
#     if ( $type eq 'ARRAY' ){
#       return $value->[0] . ',' . $value->[1]
#     }
#     if ( $type eq 'HASH' ){
#       return $value->{'lat'} . ',' . $value->{'lng'}
#     }
#   }
#   return $value;
# }


=head1 INSTALLATION

The test suite will use pre-recorded API responses. If you suspect something
changed in the API you can force the test suite to use live requests with
your API key

    PERLLIB=./lib W3W_RECORD_REQUESTS=1 W3W_API_KEY=<your key> perl t/base.t

=cut


1;
