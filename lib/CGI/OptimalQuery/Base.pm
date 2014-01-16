package CGI::OptimalQuery::Base;

use strict;
use warnings;
no warnings qw( uninitialized ); 
use CGI();
use Carp('confess');
use POSIX();
use DBIx::OptimalQuery;
use Data::Dumper;

sub can_embed { 0 }

# alias for output
sub print {
  my $o = shift;
  $o->output(@_);
}


sub new { 
  my $pack = shift;
  my $schema = shift;
  die "could not find schema!" unless ref($schema) eq 'HASH';

  my $o = bless {}, $pack;

  $$o{schema} = clone($schema);

  $$o{dbh} = $$o{schema}{dbh}
    or confess "couldn't find dbh in schema!";
  $$o{q} = $$o{schema}{q}
    or confess "couldn't find q in schema!";
  $$o{output_handler} = $$o{schema}{output_handler};
  $$o{error_handler} = $$o{schema}{error_handler};

  # check for required attributes
  confess "specified select is not a hash ref!"
    unless ref $$o{schema}{select} eq "HASH";
  confess "specified joins is not a hash ref!"
    unless ref $$o{schema}{joins} eq "HASH";
  
  # set defaults
  $$o{schema}{debug} ||= 0;
  $$o{schema}{check} = $ENV{'CGI-OPTIMALQUERY_CHECK'} 
    if ! defined $$o{schema}{check};
  $$o{schema}{check} = 0 if ! defined $$o{schema}{check};
  $$o{schema}{title} ||= "";
  $$o{schema}{options} ||= {};
  $$o{schema}{resourceURI} ||= $ENV{OPTIMALQUERY_RESOURCES} || '/OptimalQuery';

  if (! $$o{schema}{URI}) {
    $_ = ($$o{q}->can('uri')) ? $$o{q}->uri() : $ENV{REQUEST_URI}; s/\?.*$//;
    $$o{schema}{URI} = $_ or die "could not find 'URI' in schema"; 
  }

  $$o{schema}{URI_standalone} ||= $$o{schema}{URI};

  # make sure default show is in array notation
  if (! ref($$o{schema}{show}) eq 'ARRAY') {
    my @ar = grep { s/^\s+//; s/\s+$//; $_ } split /\,/, $$o{schema}{show};
    $$o{schema}{show} = \@ar;
  } 

  # make sure developer is not using illegal state_params
  if (ref($$o{schema}{state_params}) eq 'ARRAY') {
    foreach my $p (@{ $$o{schema}{state_params} }) {
      die "cannot use reserved state param name: act" if $p eq 'act';
      die "cannot use reserved state param name: module" if $p eq 'module';
      die "cannot use reserved state param name: view" if $p eq 'view';
    }
  }



  # construct optimal query object
  $$o{oq} = DBIx::OptimalQuery->new(
    'dbh'           => $$o{schema}{dbh},
    'select'        => $$o{schema}{select},
    'joins'         => $$o{schema}{joins},
    'named_filters' => $$o{schema}{named_filters},
    'named_sorts'   => $$o{schema}{named_sorts},
    'debug'         => $$o{schema}{debug},
    'error_handler' => $$o{schema}{error_handler}
  );

  # the following code is responsible for setting the disable_sort flag for all
  # multi valued selects (since it never makes since to sort a m-valued column)
  my %cached_dep_multival_status;
  my $find_dep_multival_status_i; 
  my $find_dep_multival_status;
  $find_dep_multival_status = sub {
    my $joinAlias = shift;
    $find_dep_multival_status_i++;
    die "could not resolve join alias: $joinAlias deps" if $find_dep_multival_status_i > 100;
    if (! exists $cached_dep_multival_status{$joinAlias}) {
      my $v;
      if (exists $$o{oq}{joins}{$joinAlias}[3]{new_cursor}) { $v = 0; }
      elsif (! @{ $$o{oq}{joins}{$joinAlias}[0] }) { $v = 1; }
      else { $v = $find_dep_multival_status->($$o{oq}{joins}{$joinAlias}[0][0]); }
      $cached_dep_multival_status{$joinAlias} = $v;
    }
    return $cached_dep_multival_status{$joinAlias};
  };

  # loop though all selects
  foreach my $selectAlias (keys %{ $$o{oq}{select} }) {
    $find_dep_multival_status_i = 0;

    # set the disable sort flag is select is a multi value
    $$o{oq}{select}{$selectAlias}[3]{disable_sort} = 1
      if ! $find_dep_multival_status->($$o{oq}{select}{$selectAlias}[0][0]);

    # set is_hidden flag if select does not have a nice name assigned
    $$o{oq}{select}{$selectAlias}[3]{is_hidden} = 1
      if ! $$o{oq}{select}{$selectAlias}[2];
  }



  # load saved search if defined
  $$o{schema}{savedSearchUserID} ||= undef;
  if ($$o{schema}{savedSearchUserID} =~ /^\d+$/) {

    # request to load a saved search?
    if ($$o{q}->param('OQLoadSavedSearch') =~ /^\d+$/) {
      local $$o{dbh}->{LongReadLen};
      if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
        $$o{dbh}{LongReadLen} = 900000;
        my ($readLen) = $$o{dbh}->selectrow_array("SELECT dbms_lob.getlength(params) FROM oq_saved_search WHERE id = ?", undef, $$o{q}->param('OQLoadSavedSearch'));
        $$o{dbh}{LongReadLen} = $readLen if $readLen > $$o{dbh}{LongReadLen};
      }
      my ($params) = $$o{dbh}->selectrow_array(
        "SELECT params FROM oq_saved_search WHERE id = ?",
          undef, $$o{q}->param('OQLoadSavedSearch'));
      if ($params) {
        $params = eval '{'.$params.'}'; 
        if (ref($params) eq 'HASH') {
          delete $$params{module};
          while (my ($k,$v) = each %$params) { 
            $$o{q}->param( -name => $k, -value => $v ); 
          }
        }
      }
    } 

    # request to save a search?
    elsif ($$o{q}->param('OQsaveSearchTitle') ne '') {

      # delete old searches with this user, title, uri
      $$o{dbh}->do("DELETE FROM oq_saved_search WHERE user_id = ? AND uri = ? AND oq_title = ? AND user_title = ?", undef, $$o{schema}{savedSearchUserID}, $$o{schema}{URI},$$o{schema}{title}, $$o{q}->param('OQsaveSearchTitle'));

      $$o{q}->param('queryDescr', $$o{q}->param('OQsaveSearchTitle'));

      my %data;
      foreach my $p (qw( show filter sort page rows_page queryDescr hiddenFilter )) {
        $data{$p} = $$o{q}->param($p);
      }
      if (ref($$o{schema}{state_params}) eq 'ARRAY') {
        foreach my $p (@{ $$o{schema}{state_params} }) {
          my @v = $$o{q}->param($p);
          $data{$p} = \@v;
        }
      }

      local $Data::Dumper::Indent = 0;
      local $Data::Dumper::Quotekeys = 0;
      local $Data::Dumper::Pair = '=>';
      local $Data::Dumper::Sortkeys = 1;
      my $params = Dumper(\%data);
      $params =~ s/^[^\{]+{//;
      $params =~ s/\}\;\s*$//;

      if ($$o{dbh}{Driver}{Name} eq 'Oracle') {
        $$o{dbh}->do("INSERT INTO oq_saved_search (id,user_id,uri,oq_title,user_title,params) VALUES (s_oq_saved_search.nextval,?,?,?,?,?)", undef, $$o{schema}{savedSearchUserID}, $$o{schema}{URI}, $$o{schema}{title}, $$o{q}->param('OQsaveSearchTitle'), $params);
      } else {
        $$o{dbh}->do("INSERT INTO oq_saved_search (user_id,uri,oq_title,user_title,params) VALUES (?,?,?,?,?)", undef, $$o{schema}{savedSearchUserID}, $$o{schema}{URI}, $$o{schema}{title}, $$o{q}->param('OQsaveSearchTitle'), $params);
      }
    }
  }

  return $o;
}

sub oq  { $_[0]{oq}  }

# ----------- UTILITY METHODS ------------------------------------------------

sub escape_html      { CGI::escapeHTML($_[1]) }
sub escape_uri       { CGI::escape($_[1])     }
sub escape_js        {
  my $o = shift;
  $_ = shift;
  s/\\/\\x5C/g;  #escape \
  s/\n/\\x0A/g;  #escape new lines
  s/\'/\\x27/g;  #escape '
  s/\"/\\x22/g;  #escape "
  s/\&/\\x26/g;  #escape &
  s/\r//g;       #remove carriage returns
  s/script/scr\\x69pt/ig; # make nice script tags
  return $_;
}
sub commify {
  my $o = shift;
  my $text = reverse $_[0];
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
} # Commify


my %no_clone = ('dbh' => 1, 'q' => 1);
sub clone {
  my $thing = shift;
  if (ref($thing) eq 'HASH') {
    my %tmp;
    while (my ($k,$v) = each %$thing) { 
      if (exists $no_clone{$k}) { $tmp{$k} = $v; }
      else { $tmp{$k} = clone($v); }
    }
    $thing = \%tmp;
  } elsif (ref($thing) eq 'ARRAY') {
    my @tmp;
    foreach my $v (@$thing) { push @tmp, clone($v); }
    $thing = \@tmp;
  } 
  return $thing;
}


1;
