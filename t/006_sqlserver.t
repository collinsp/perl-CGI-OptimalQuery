# -*- perl -*-


=comment

# to execute these tests, supply database connection info

export SQLSERVER_DSN="dbi:ODBC:DRIVER={ODBC Driver 11 for SQL Server};Server=mysqlserver.com;database=testoq;MARS_Connection=yes"
export SQLSERVER_USER='testoq'
export SQLSERVER_PASS='testoq'
perl -I../lib ./006_sqlserver.t


# sudo yum install perl-DBD-ODBC

# Download Linux ODBC Driver for SQLServer:
#  http://www.microsoft.com/en-us/download/details.aspx?id=36437
# tar -xvf msodbcsql-11.0.2270.0.tar.gz
# cd msodbcsql-11.0.2270.0
# su
# ./build_dm.sh
# ./install.sh install

=cut

# t/002_postgrestest.t - check module loading and create testing directory
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
  skip "ENV: SQLSERVER_DSN,SQLSERVER_USER,SQLSERVER_PASS not configured", $TOTAL_TESTS unless $ENV{SQLSERVER_DSN};

  $dbh = DBI->connect($ENV{SQLSERVER_DSN}, $ENV{SQLSERVER_USER}, $ENV{SQLSERVER_PASS}, { RaiseError => 1, PrintError => 1 });
  pass("connect") if $dbh; 

  dropall();

  # test people
  $dbh->do("CREATE TABLE ".$prefix."person ( person_id INTEGER, name VARCHAR(100), birthdate DATE )");
  my @people = (
    [1, 'Harrison Ford', '1942-07-13'],
    [2, 'Mark Hamill', '1951-09-25'],
    [3, 'Irvin Kershner', '1923-04-29'],
    [4, 'Richard Marquand', '1938-01-01'],
    [5, 'Steven Spielberg', '1946-12-18'],
  );
  $dbh->do("INSERT INTO ".$prefix."person VALUES (?,?,?)", undef, @$_) for @people;

  # test movies
  $dbh->do("CREATE TABLE ".$prefix."movie ( movie_id INTEGER, name VARCHAR(100), releaseyear INTEGER, director_person_id INTEGER )");
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

  # create a test optimal query
  my $buf;
  my $o = CGI::OptimalQuery->new({
    'URI' => '/Movies',
    'dbh' => $dbh,
    'select' => {
      'U_ID' => ['movie','movie.movie_id','Movie ID'],
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
  });
  pass("create object");

  $o->output();

  ok($buf =~ /Return\ of\ the\ Jedi/s, 'lowercase select alias');
  ok($buf =~ /Harrison Ford\, Mark Hamill/s, 'multival field');
}

