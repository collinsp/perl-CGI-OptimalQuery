#!/usr/bin/perl

use strict;
use DBI();
use CGI::OptimalQuery();
use FindBin qw($Bin);

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=test_data.db","","");

my %schema = (
  'dbh' => $dbh,
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
