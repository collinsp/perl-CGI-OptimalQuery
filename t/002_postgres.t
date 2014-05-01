# -*- perl -*-


=comment
# to execute these tests, you must connect to an existing postgres database
# the test will create some temp tables that will get cleaned up automatically
# to create a new test database
sudo su - postgres
psql
CREATE DATABASE testoq;
CREATE USER testoq PASSWORD 'testoq';
GRANT ALL PRIVILEGES ON DATABASE testoq TO testoq;
exit # exit psql
exit # exit login as postgres

# define connection info
export PG_DSN="dbi:Pg:dbname=testoq;hostaddr=127.0.0.1"
export PG_USER=testoq
export PG_PASS=testoq
perl -I../lib ./002_postgrestest.t

# when done with tests, delete temp database
sudo su - postgres
psql
DROP USER testoq;
DROP DATABASE testoq;
exit
=cut

# t/002_postgrestest.t - check module loading and create testing directory
use strict;
use File::Temp();
use CGI::OptimalQuery();
use DBI();

use Test::More tests => 5;
my $TOTAL_TESTS = 5;

use warnings;
no warnings qw( uninitialized );


my $prefix = 'oqtestdeleteme_';
my $dbh;

sub dropall {
  local $$dbh{RaiseError} = 0;
  local $$dbh{PrintError} = 0;
  $dbh->do("DROP TABLE ".$prefix.$_) for (qw( person movie moviecast ));
}

END {
  if ($dbh) {
    dropall();
    eval { $dbh->disconnect(); }; if ($@) { print STDERR $@; }
  }
}
SKIP: {
  skip "ENV: PG_DSN,PG_USER,PG_PASS not configured", $TOTAL_TESTS unless $ENV{PG_DSN};

  $dbh = DBI->connect($ENV{PG_DSN}, $ENV{PG_USER}, $ENV{PG_PASS}, { RaiseError => 1, PrintError => 1 });
  pass("connect") if $dbh; 

  dropall();

  # test people
  $dbh->do("CREATE TABLE ".$prefix."person ( person_id INTEGER, name TEXT, birthdate DATE )");
  my @people = (
    [1, 'Harrison Ford', '1942-07-13'],
    [2, 'Mark Hamill', '1951-09-25'],
    [3, 'Irvin Kershner', '1923-04-29'],
    [4, 'Richard Marquand', '1938-01-01'],
    [5, 'Steven Spielberg', '1946-12-18'],
  );
  $dbh->do("INSERT INTO ".$prefix."person VALUES (?,?,?)", undef, @$_) for @people;

  # test movies
  $dbh->do("CREATE TABLE ".$prefix."movie ( movie_id INTEGER, name TEXT, releaseyear INTEGER, director_person_id INTEGER )");
  my @movies = (
    [1, 'The Empire Strikes Back', 1980, 3],
    [2, 'Return of the Jedi', 1983, 4],
    [3, 'Raiders of the Lost Ark', 1981, 5]
  );
  $dbh->do("INSERT INTO ".$prefix."movie VALUES (?,?,?,?)", undef, @$_) for @movies;

  # test cast
  $dbh->do("CREATE TABLE ".$prefix."moviecast ( movie_id INTEGER, person_id INTEGER)");
  my @cast = ([1,1],[1,2],[2,1],[2,2],[3,1]);
  $dbh->do("INSERT INTO ".$prefix."moviecast VALUES (?,?)", undef, @$_) for @cast;
  pass("create testdb");

  my $buf;

  my $get_schema = sub {{
    'URI' => '/Movies',
    'dbh' => $dbh,
    'select' => {
      'ID' => ['movie','movie.movie_id','Movie ID'],
      'name' => ['movie','movie.name','Movie Name'],
      'DIRECTOR' => ['director', 'director.name', "Director's Name"],
      'cast' => ['moviecastperson', 'moviecastperson.name', 'All Cast (seprated by commas)'],
      'DIRECTOR_BITHDATE' => ['director', 'director.birthdate', 'Director Birthdate'],
      'RELEASE_YEAR' => ['movie', 'movie.releaseyear', 'Release Year']
    },
    'output_handler' => sub { $buf .= $_[0] },
    'module' => 'CSV',
    'joins' => {
      'movie' => [undef, $prefix.'movie AS movie'],
      'director' => ['movie', 'LEFT JOIN '.$prefix.'person AS director ON (movie.director_person_id = director.person_id)'],
      'moviecast' => ['movie', 'JOIN '.$prefix.'moviecast AS moviecast ON (movie.movie_id = moviecast.movie_id)', undef, { new_cursor => 1 }],
      'moviecastperson' => ['moviecast', 'JOIN '.$prefix.'person AS moviecastperson ON (moviecast.person_id=moviecastperson.person_id)']
    }
  }};


  # create a test optimal query
  { $buf = '';
    my $s = $get_schema->();
    my $o = CGI::OptimalQuery->new($s);
    $o->output();
    ok($buf =~ /Return\ of\ the\ Jedi/s, 'lowercase select alias');
  }

  { $buf = '';
    my $s = $get_schema->();
    $$s{filter} = "[cast] contains 'hamill'";
    my $o = CGI::OptimalQuery->new($s);
    $o->output();
    ok($buf =~ /Harrison Ford\, Mark Hamill/s, 'multival field');
  }

  # test filter multival using new cursor dep wth inline view in joins that has a join
  # this test was used to fix a bug where OQ was not extracting the corelated join properly
  { $buf = '';
    my $s = $get_schema->();
    $$s{joins}{moviecast}[1] = "LEFT JOIN (SELECT q1.* FROM ".$prefix."moviecast q1 join ".$prefix."moviecast q2 ON (q1.movie_id=q2.movie_id) WHERE 'abc'='abc') as moviecast ON (movie.movie_id = moviecast.movie_id)";
    $$s{filter} = "[cast] contains 'harrison'";
    my $o = CGI::OptimalQuery->new($s);
    $o->output();
    ok($buf =~ /Spielberg/s, 'inline view in joins test');
  }
}

