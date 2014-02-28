#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../lib"; # include project lib

use DBI();
use CGI::OptimalQuery();

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=db/dat.db","","");

my %schema = (
  'dbh' => $dbh,
  'savedSearchUserID' => 12345,
  'title' => 'Manufacturers',
  'select' => {
    'U_ID' => ['manufact', 'manufact.id', 'SYS ID', { always_select => 1 }],
    'NAME' => ['manufact', 'manufact.name', 'Name']
  },
  'show' => "NAME,MANUFACT",
  'joins' => {
    'manufact' => [undef, 'manufact']
  },
  'options' => {
    'CGI::OptimalQuery::InteractiveQuery' => {
      'editLink' => 'record.pl'
    }
  }
);

CGI::OptimalQuery->new(\%schema)->output();