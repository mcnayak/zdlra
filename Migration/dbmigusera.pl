#!/usr/bin/perl
use strict;
use Getopt::Long qw(:config no_ignore_case);
use POSIX ":sys_wait_h";
use vars qw/ %opt /;
our %transfer = ();
our $context = \%opt;
our $xttprop;
our $myversion = "1.0";
our %props;
our @tablespaces = ();
our @properties = ();
our $rollParallel = 0;
our $tmp;
our @forkArray = ();
our $errfile;
our ($resFile, $recFile, $incrFile, $dfCopyFile, $failedDf, $tmpMisc, $tstamp);
our $dbId;

$| = 1;
my $rman = "$ENV{ORACLE_HOME}/bin/rman";
my $rman_ra_args1 = " target ";
my $rman_ra_args2 = " catalog ";

my $sqlplus = "$ENV{ORACLE_HOME}/bin/sqlplus -s";
my $sqlplus_ra_args;
my $sqlplus_sys_args;

###############################################################################
# Function : usage
# Purpose  : Message about this program and how to use it
###############################################################################
sub usage
{
   print STDERR << "EOF";

   This program prepares, backsup and rollsforward tablespaces
   for cross-platform transportable tablespaces.

    usage: $0
                  {[--restore] || [--recover] || 
                   [--setuprestore] || [--setuprecover] 
                   [--sqlsys]
                   [--sqlrasys]
                   [--rmantarget]
                   [--rmanra]
                   [--help|-h]}

     --restore: Restore the datafiles
     --recover: Recover the datafiles
     --setuprestore: Setup the datafile information required to be restored
     --setuprecover: Setup the datafile information required to be recovered
     --sqlsys:   Connect string to the source database for sqlplus
     --sqlrasys: Connect to the RA as catalog owner
     --rmantarget: Connect string to RMAN in destination database
     --rmanra: Connect to catalog with the ra user
EOF
   exit;
}

###############################################################################
# Function : touchErrFile
# Purpose  : Create the error file if requested
###############################################################################
sub touchErrFile
{
   my $message = $_[0];

   open ERRFILE, ">>$errfile";
   print ERRFILE "$message\n";
   close ERRFILE;
}

###############################################################################
# Function : Die
# Purpose  : Print message and exit
###############################################################################
sub Die
{
    my $message = $_[0];

    touchErrFile($message);
die "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Error:
------
$message
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
";
}

###############################################################################
# Function : debugprint
# Purpose  : print if debug value is >= passed debug level
###############################################################################
sub debugprint
{
   my $message    = $_[0];
   my $debuglevel = $_[1];

   if ($context -> {"debug"} >= $debuglevel)
   {
      print $_[0] . "\n";
   }
}

###############################################################################
# Function : debug
# Purpose  : print with level being 1
###############################################################################
sub debug
{
   debugprint ($_[0], 1);
}

###############################################################################
# Function : debug3
# Purpose  : print with level being 3
###############################################################################
sub debug3
{
   debugprint ($_[0], 3);
}

###############################################################################
# Function : debug4
# Purpose  : print with level being 4
###############################################################################
sub debug4
{
   debugprint ($_[0], 4);
}

###############################################################################
# Function : Unlink
# Purpose  : Delete the file if the debug level is less than 2
###############################################################################
sub Unlink
{
   my $delFile = $_[0];
   my $force   = $_[1];

   if ($force || ($context->{"debug"} <= 0))
   {
      unlink ($delFile);
   }
}

###############################################################################
# Function : checkErrFile
# Purpose  : check if the error file exists
###############################################################################
sub checkErrFile
{
   if (-e $errfile)
   {
die "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Error:
------
      Some failure occurred. Check $errfile for more details
      If you have fixed the issue, please delete $errfile and run it
      again OR run xttdriver.pl with -L option
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
";
   }
}

sub readFile
{
   my $inFile = $_[0];
   my @filArray = ();

   open FILE, "$inFile" or Die ("Unable to open file $inFile");
   while (<FILE>)
   {
      my $x = Trim ($_);
      if ($x !~ m/#.*/)
      {
         push (@filArray, $x);
      }
   }
   close FILE;

   return @filArray;
}

###############################################################################
# Function : checkErrFile
# Purpose  : check if the error file exists
###############################################################################
sub checkErrFile
{
   if (-e $errfile)
   {
      {
die "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Error:
------
      Some failure occurred. Check $errfile for more details
      If you have fixed the issue, please delete $errfile and run it
      again OR run xttdriver.pl with -L option
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
";
      }
   }
}

###############################################################################
# Function : checkMove
# Purpose  : Check if entry is present and move it
###############################################################################
sub checkMove
{
   my $srcPath = $_[0];
   my $dstPath = $_[1];

   if (!$dstPath)
   {
      $dstPath = $tmpMisc;
      if ($srcPath =~ m/.*\/(.*)/)
      {
         $dstPath = $dstPath."/".$1;
         if (-e $dstPath)
         {
            $dstPath = $dstPath.GetTimeStamp();
         }
      }
   }

   if (-e $srcPath)
   {
      system("\\mv $srcPath $dstPath");
   }
}

###############################################################################
# Function : PrintMessage
# Purpose  : Print the message that is passed to it
# Inputs   : Any text
# Outputs  : None
# NOTES    : None
###############################################################################
sub PrintMessage
{
    my $message = $_[0];

print "
--------------------------------------------------------------------
$message
--------------------------------------------------------------------
";
}

sub delDir 
{
  my $dirtodel = pop;
  my $sep = '/'; #change this line to "/" on linux.
  my @files;

  opendir(DIR, $dirtodel);
  @files = readdir(DIR);
  closedir(DIR);
 
  @files = grep { !/^\.{1,2}/ } @files;
  @files = map { $_ = "$dirtodel$sep$_"} @files;
 
  @files = map { (-d $_)?delDir($_):unlink($_) } @files;
 
  rmdir($dirtodel);
}

###############################################################################
# Function : parseArg
# Purpose  : Command line options processing
# Inputs   : None
# Returns  : None
###############################################################################
sub parseArg
{
   GetOptions ($context,
               'clean',
               'debug|d:i',
               'restore|R',
               'recover|X',
               'setuprestore|s',
               'setuprecover|S',
               'sqlsys=s',
               'sqlrasys=s',
               'rmantarget=s',
               'rmanra=s',
               'ignoreerrors',
               'version|v',
               'deletefile|L',
               'help|h'
              ) or usage();

   if ($context->{"help"})
   {
      usage();
   }
   
   if (! defined($context->{"xttdir"}))
   {
      if (defined($ENV{'TMPDIR'}))
      {
         $tmp = $ENV{'TMPDIR'};
      }
      else
      {
         $tmp = "/tmp/";
      }
   }
   else
   {
      $tmp = $context->{"xttdir"};
   }

   $resFile    = "$tmp/res.txt";
   $recFile    = "$tmp/rec.txt";

   $tmp = "$tmp/ramigratedb";

   unless (-e $tmp and -d $tmp)
   {
      system ("mkdir $tmp");
   }

   $errfile    = "$tmp/FAILED";
   $incrFile   = "$tmp/incr.txt";
   $dfCopyFile = "$tmp/dfcopy.txt";
   $failedDf   = "$tmp/faileddf.txt";
   $tstamp = GetTimeStamp();

   if ($context->{"deletefile"})
   {
      Unlink($errfile, 1);
   }

   checkErrFile();

   if ($context->{"clean"})
   {
      delDir($tmp);
      exit (1);
   }

   if ($context->{"version"})
   {
      PrintMessage ("Version is $myversion");
      exit (1);
   }

   if (defined ($context->{"debug"}) && ($context->{"debug"} == 0))
   {
      $context->{"debug"} = 1;
   }

   if (defined($context->{"propfile"}))
   {
      $xttprop = $context->{"propfile"};
   }
   else
   {
      $xttprop = "xtt.properties";
   }
   
   if ($context->{"setuprestore"} ||
       $context->{"setuprecover"})
   {
      if (!defined($context->{"sqlrasys"}))
      {
         Die("sqlrasys not defined");
      }
      $sqlplus_ra_args = $context->{"sqlrasys"};
   }

   if (!defined($context->{"sqlsys"}))
   {
      $sqlplus_sys_args = " / as sysdba";
   }
   else
   {
      $sqlplus_sys_args = $context->{"sqlsys"};
   }

   if ($context->{"restore"} ||
       $context->{"recover"})
   {
      if (!defined($context->{"rmanra"}))
      {
         Die("rmanra not defined");
      }
      $rman_ra_args2 = $rman_ra_args2." ".$context->{"rmanra"};
   }

   if (!defined($context->{"rmantarget"}))
   {
      $rman_ra_args1 = $rman_ra_args1." \/ ";
   }
   else
   {
      $rman_ra_args1 = $rman_ra_args1.$context->{"rmantarget"};
   }

   if ($context->{"restore"})
   {
      $tmpMisc = "$tmp/restore_"."$tstamp/";
   }
   if ($context->{"recover"})
   {
      $tmpMisc = "$tmp/recover_"."$tstamp/";
   }
   elsif ($context->{"setuprestore"})
   {
      $tmpMisc = "$tmp/setuprestore_"."$tstamp/";
   }
   elsif ($context->{"setuprecover"})
   {
      $tmpMisc = "$tmp/setuprecover_"."$tstamp/";
   }
   else
   {
      $tmpMisc = "$tmp/$tstamp/";
   }
   system ("mkdir $tmpMisc");
}

###############################################################################
# Function : parseProperties
# Purpose  : Parse the properties file xtt.properties
###############################################################################
sub parseProperties
{
   PrintMessage ("Parsing properties");

   # Check if any failure occured and stop exection
   #checkErrFile();

   my @properties = qw(tablespaces sbtlibparms resparallel ttsnames);
   open my $in, "$xttprop" or Die "$xttprop not found: $!";

   while(<$in>)
   {
      next if /^#/;
      $props{$1}=$2 while m/(\S+?)=(.+)/g;
   }
   close $in;

   if ($context -> {"debug"})
   {
      foreach my $pkey (keys %props)
      {
         print "Key: $pkey\n";
         print "Values: $props{$pkey}\n";
      }
   }
   @tablespaces = split(/,/, $props{'tablespaces'});

   PrintMessage ("Done parsing properties");

   if (!defined($props{'resparallel'}))
   {
      $props{'resparallel'} = 3;
   }
   $rollParallel = $props{'resparallel'};

   #print $props{'resparallel'}." is defined\n";
}

###############################################################################
# Function : PrintMessage
# Purpose  : Print the message that is passed to it
# Inputs   : Any text
# Outputs  : None
# NOTES    : None
###############################################################################
sub DebugPrintMessage
{
   my $message    = $_[0];
   my $debuglevel = $_[1];

   if ($context -> {"debug"} >= $debuglevel)
   {
      PrintMessage($message);
   }
}

###############################################################################
# Function : PrintMessage
# Purpose  : Print the message that is passed to it
# Inputs   : Any text
# Outputs  : None
# NOTES    : None
###############################################################################
sub debug3Message
{
   my $message    = $_[0];
   my $debuglevel = $_[1];

   DebugPrintMessage($message, 3);
}

sub Print
{
   my $str = $_[0];
   open FILE, ">>$tmp/a.lox";
   $str = Trim($str);
   if ($str ne '')
   {
      print FILE "$str\n";
   }
   close FILE;
}

sub RunSQLCmd
{
   my $sqlplus_args = $_[0];
   my $sqlplus_cmd = $_[1];
   my @resArray = ();

   open( my $run, "$sqlplus $sqlplus_args $sqlplus_cmd|");
   while (<$run>)
   {
      my $return = $_;
      push(@resArray,$return);
      chomp($return);
      if (($return =~ /ORA[-][0-9]/) || ($return =~ /SP2-.*/))
      {
         PrintMessage ("Error $sqlplus_cmd $return");
         exit;
      }
      Print($return);
   }
   close $run;
   debug4("$sqlplus_cmd returned");
   debug4Array(\@resArray);
   return @resArray;
}

sub RunRMANCmd
{
   my $rman_args = $_[0];
   my $rman_cmd = $_[1];
   my @resArray = ();

   debug4 ("$rman $rman_args $rman_cmd");
   open( my $run, "$rman $rman_args cmdfile=$rman_cmd|");
   while (<$run>)
   {
      my $return = $_;
      chomp($return);
      if (($return =~ /ORA[-][0-9]/) || ($return =~ /SP2-.*/))
      {
         PrintMessage ("Error $rman_cmd $return");
         @resArray = ();
         return @resArray;
      }
      push(@resArray,"$return\n");
      Print($return);
   }
   close $run;
   debug3 "$rman_cmd returned @resArray\n";
   return @resArray;
}

sub Trim
{
    my $string = $_[0];
    #chomp($string);
    chomp($string);
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    $string =~ s/\n|\t//;
    return $string;
}

sub GetDFList
{
   my @fileArray = (@_);
   my %tbsList;
   my $tbsHash = \%tbsList;
   my @dfArray = ();
   my @dfNoArray = ();

   foreach my $x (@fileArray)
   {
      my $y = $x;
      chomp($x);
      chomp($y);
      $y = Trim($y);
      if (length($y) > 0)
      {
         if ($y =~ m/name=(.*?)\s+dfile=(.*?)\s+crp=(.*)/)
         {
            my $tbname = $1;
            my $dfno = $2;
            my $crpscn = $3;

            my $no = scalar($tbsHash->{$tbname}->{"fnos"});

            if (defined($tbsHash->{$tbname}->{"fnos"}))
            {
               my @dfHashArray = @{$tbsHash->{$tbname}->{"fnos"}};
               push (@dfHashArray, $dfno);
               $tbsHash->{$tbname}->{"fnos"} = [@dfHashArray];
               push(@dfNoArray, $dfno);
            }
            else
            {
               my @dfHashArray = ();
               push (@dfHashArray, $dfno);
               $tbsHash->{$tbname}->{"fnos"} = [@dfHashArray];
               push(@dfNoArray, $dfno);
            }
            $tbsHash->{$tbname}->{$dfno}->{"crtscn"} = $crpscn;
         }
      }
   }
   return (\%tbsList, @dfNoArray);
}

sub PrintDfList
{
   my $tbsHash = $_[0];

   if ($context->{"debug"} >= 3)
   {
      foreach my $keys (keys %{$tbsHash})
      {
         my @dfHashArray = @{$tbsHash->{$keys}->{"fnos"}};
         foreach my $x (@dfHashArray)
         {
            print $x, $tbsHash->{$keys}->{$x}->{"crtscn"}."\n";
         }
      }
   }
}

###############################################################################
# Function : checkEleDfnoExists
# Purpose  : Check if duplicate element exists in array
###############################################################################
sub checkEleDfnoExists
{
   my @array = @{$_[0]};
   my $ele = $_[1];

   chomp ($ele);

   foreach my $x (@array)
   {
      chomp ($x);

      if ($x =~ m/(.*):::.*/)
      {
         if ($1 == $ele)
         {
            return 1;
         }
      }
   }

   return 0;
}

###############################################################################
# Function : checkEleRecDfnoExists
# Purpose  : Check if duplicate element exists in array
###############################################################################
sub checkEleRecDfnoExists
{
   my @array = @{$_[0]};
   my $ele = $_[1];

   chomp ($ele);

   foreach my $x (@array)
   {
      chomp ($x);
      print $x, $ele."\n";
      if ($x =~ m/(.*?),.*/)
      {
         my $df1 = $1;
         if ($df1 == $ele)
         {
            return 1;
         }
      }
   }

   return 0;
}

###############################################################################
# Function : checkEleExists
# Purpose  : Check if duplicate element exists in array
###############################################################################
sub checkEleExists
{
   my @array = @{$_[0]};
   my $ele = $_[1];

   chomp ($ele);

   foreach my $x (@array)
   {
      chomp ($x);
      if ($x eq $ele)
      {
         return 1;
      }
   }

   return 0;
}

###############################################################################
# Function : getPlatId
# Purpose  : To get name of source platform
###############################################################################
sub getPlatId
{
   my $sqlOutput ;
   my @resSysArray = ();

   my $sqlplus_sys_cmd =
"<<EOF
   set line 2000
   set serveroutput on
   set echo on
   set heading off
   select 'platform_id='||platform_id platid
     from v\\\$database;
   quit
EOF\n";

   @resSysArray = RunSQLCmd($sqlplus_sys_args, $sqlplus_sys_cmd);
   foreach my $x (@resSysArray)
   {
      if ($x =~ m/.*platform_id=(.*?)\s+/)
      {
         #print $1."goood\n";
      }
   }
   #print "@resSysArray\n";
   return 2;
}

sub appendIncrFile
{
   my $inFile = $_[0];
   my $outFile = $incrFile;
   my @inArray;
   my @outArray;

   open FILE, "$inFile";
   @inArray = <FILE>;
   close FILE;

   open FILE, "$outFile";
   @outArray = <FILE>;
   close FILE;

   foreach my $x (@inArray)
   {
      if (scalar @outArray != 0)
      {
         chomp($x);
         Trim($x);
         if (! checkEleExists (\@outArray, $x))
         {
            open FILE, ">>$outFile";
            print FILE $x."\n";
            close FILE;
         }
      }
      else
      {
         open FILE, ">>$outFile";
         print FILE @inArray;
         close FILE;
      }
   }
}

sub findDiffArray
{
   my ($array1P, $array2P) = @_;
   my @array1 = @$array1P;
   my @array2 = @$array2P;

   my %array1H = map {($_, 1)} @array1;
   my @diffArray = grep {!$array1H{$_}} @array2;         
   
   return (\@diffArray);
}

sub CreateResRecInpFile
{
   my ($resArrayP, $dfTBArrayP, $filStrC) = @_;
   my @resArray = @$resArrayP;
   my @dfTBArray = @$dfTBArrayP;
   my @filFoundArray = ();
   my $platId = 0;
   my $outfile ;
   my $foundBkp = 0;

   if ($context->{"setuprestore"})
   {
      $outfile = $resFile;
   }
   elsif ($context->{"setuprecover"})
   {
      $outfile = $recFile;
   }

   $platId = getPlatId();

   open FILE, ">$outfile";
   foreach my $x (@resArray)
   {
      chomp($x);
      if ($x =~ m/.*handle=(.*?)\s+file=(.*?)\s+ckp_scn=(.*?)\s+bskey=(.*)/)
      {
         print FILE "$2,$platId,$1,$3,$4,0\n";
         $foundBkp = $foundBkp + 1;
         push(@filFoundArray, $2);
      }
   }
   close FILE;

   if ($foundBkp == 0)
   {
      Die ("No backups found for given tablespace, perform backups and ".
           "rerun script with -L option to remove error file");
   }
   elsif ($foundBkp != $filStrC)
   {
      my $diffF = $filStrC - $foundBkp;
      my $diffArray = findDiffArray (\@filFoundArray, \@dfTBArray);
      my $diffArrayStr = join(',', @$diffArray);
      Die ("Backups not found for $diffF datafiles $diffArrayStr.".
           " Perform backups and ".
           "rerun script with -L option to remove error file");
   }
   appendIncrFile($outfile);
}

sub printArray
{
   my ($printMessage, $debuglevel) = @_;

   if ($context -> {"debug"} < $debuglevel)
   {
      return;
   }

   foreach my $x (@$printMessage)
   {
      $x = Trim($x);
      if ($x ne '')
      {
         print "$x\n";
      }
   }
}

sub debug3Array
{
   my ($printLMessage) = @_;
   my $debugLevel = 3;

   printArray(\@$printLMessage, $debugLevel);
}

sub debug4Array
{
   my ($printLMessage) = @_;
   my $debugLevel = 4;

   printArray(\@$printLMessage, $debugLevel);
}

###############################################################################
# Function : getPlatName
# Purpose  : To get name of source platform
###############################################################################
sub getPlatName
{
   my $platid = $_[0];
   my $sqlOutput ;
   my @resSysArray = ();
   my $platName = '';
   my $sqlplus_sys_cmd =
"<<EOF
   set line 2000
   set serveroutput on
   set echo on
   set heading off
   select 'platform_name='||platform_name platform_name
     from v\\\$transportable_platform
    where platform_id = $platid;
   quit
EOF\n";

   @resSysArray = RunSQLCmd($sqlplus_sys_args, $sqlplus_sys_cmd);
   foreach my $x (@resSysArray)
   {
      if ($x =~ m/.*platform_name=(.*)/)
      {
         $platName = Trim($1);
      }
   }
   debug3Array(\@resSysArray);
   return $platName;
}

sub UpdateForkArray
{
   my ($pid, $parallel) = @_;

   if ($#forkArray < $parallel)
   {
      push (@forkArray, $pid);
   }
   else
   {
      foreach my $index (0 .. $#forkArray)
      {
         my $x = $forkArray[$index];
         if ($x == 0)
         {
            $forkArray[$index] = $pid;
            last;
         }
      }
   }
}

###############################################################################
# Function : ChecktoProceed
# Purpose  : When running the roll forward in parallel, we will check if we can
#            fork any more jobs
###############################################################################
sub ChecktoProceed
{
   my $parallel = $_[0];
   # Check if any failure occured and stop exection
   checkErrFile();
   my $running = 0;

   if ($#forkArray <= 0)
   {
      return;
   }
   do
   {
      $running = 0;
      foreach my $index (0 .. $#forkArray)
      {
         my $x = $forkArray[$index];
         if ($x <= 0)
         {
            next;
         }
         my $kid = waitpid($x, WNOHANG);
         if ($kid >= 0)
         {
            $running = $running + 1;
         }
         else
         {
            $forkArray[$index] = 0;
         }
      }
   } while ($running >= $parallel);

   return;
}

sub getVBName
{
   my ($fno, $ckpScn, $platId, $bsKey, $resEnt, $filArrayP) = @_;
   my $sqlOutput ;
   my @resSysArray = ();
   my $platName = '';
   my $sqlplus_ra_cmd =
"<<EOF
   set line 2000
   set serveroutput on
   set echo on
   set heading off
   SELECT 'handle='||handle handle,
          'ckp_scn='||bdf.CKP_SCN
     from bs,
          bp,
          bdf
    where bdf.incr_scn = $ckpScn and
       bp.db_key = $dbId and
       bp.bs_key = bs.bs_key and
       bp.status = 'A' and
       bs.incr_level = 1 and
       bs.bs_key  = bdf.bs_key and
       bdf.file# = $fno and
       bp.vb_key is not null;
   quit
EOF\n";

   @resSysArray = RunSQLCmd($sqlplus_ra_args, $sqlplus_ra_cmd);
   $resEnt = 0;
   foreach my $x (@resSysArray)
   {
      if ($x =~ m/.*handle=(.*?)\s+ckp_scn=(.*)/)
      {
         $resEnt = 1;
         debug3 "getVBName: $fno,$platId,$1,$2,1\n";
         my $fStr = "$fno,$platId,$1,$2,$bsKey,1\n";
         push (@$filArrayP, $fStr);
      }
   }
   if ($resEnt == 0)
   {
      Die ("No incremental backups found for datafile $fno, perform backups and ".
           "rerun script with -L option to remove error file");
   }
   return;
}

sub updateRecoverFile
{
   my ($array1P, $array2P) = @_;
   my @array1 = @$array1P;
   my @array2 = @$array2P;
   my @finArray;
   my $outFile = $recFile;
   my @existArray = ();
   
   foreach my $x (@array1)
   {
      $x = "#".$x;
      push (@finArray, $x);
   }
   
   foreach my $x (@array1)
   {
      my $count = 0;
      foreach my $y (@array2)
      {
         if ($x =~ m/#(.*?),.*/)
         {
            my $fno1 = $1;
            my $fno2 = 0;
            print "$count:$x, $y\n";
            if ($y =~ m/(.*?),.*/)
            {
               $fno2 = $1;
               if ($fno2 == $fno1)
               {
                  print "Need to removed $fno1\n";
                  push(@finArray, $y."\n");
                  delete $array2[$count];
                  last;
               }
            }
         }
         $count = $count + 1;
      }
   }
   
   print "final arary\n";
   debug3Array(\@finArray);

   open FILER, "$outFile";
   @existArray = <FILER>;
   close FILER;
   open FILE, ">$outFile";
   foreach my $x (@existArray)
   {
      $x = Trim($x);
      if ($x =~ m/#.*/)
      {
         print FILE "$x\n";
      }
   }

   foreach my $x (@finArray)
   {
      $x = Trim($x);
      print FILE "$x\n";
   }
   close FILE;
}

sub creUpdRecFile
{
   my @filArray  = ();
   my $platName = '';
   my $ckpScn;
   my @updFileArray = ();

   if (-e $recFile)
   {
      @filArray = readFile($recFile);
      if (scalar @filArray == 0)
      {
         @filArray = readFile($resFile);
      }
   }
   else
   {
      @filArray = readFile($resFile);
   }

   getDBID();

   foreach my $x (@filArray)
   {
      my ($platid, $fno, $bkpSet, $bsKey, $useRec);
      chomp($x);
      debug3("creUpdRecFile:$x\n");
      if ($x =~ m/(.*?),(.*?),(.*?),(.*?),(.*?),(.*)/)
      {
         $platid = $2;
         $fno = $1;
         $bkpSet = $3;
         $ckpScn = $4;
         $bsKey = $5;
         $useRec = $6;
         if ($platName eq '')
         {
            $platName = getPlatName($platid);
         }
         getVBName($fno, $ckpScn, $platid, $bsKey, $x, \@updFileArray);
         debug3Array(\@updFileArray);
      }
   }
   updateRecoverFile(\@filArray, \@updFileArray); 
}

sub updateRecoverDFCopy
{
   my @outputArray = @_;
   my @dfSucArray = ();
   my $dfNo;

   open FILE, ">>$dfCopyFile";

   foreach my $x (@outputArray)
   {
      if ($x =~ m/restoring foreign file (.*?)\s+to\s+(.*)/)
      {
         $dfNo = $1;
         print FILE "$1:::$2\n";
         push (@dfSucArray, $1);
      }
   }
   close FILE;

   open FILE, "$failedDf";
   @outputArray = <FILE>;
   close FILE;

   for (my $i = $#outputArray; $i > -1; $i--)
   {
      #  Delete element here if it matches.
      if ($outputArray[$i] =~ m/(.*?),.*/)
      {
         if ($1 == $dfNo)
         {
            splice @outputArray, $i, 1;
            last;
         }
      }
   }

   if ($#outputArray > 0)
   {
      open FILE, ">$failedDf";
      print FILE @outputArray;
      close FILE;
   }
}

sub getDFCopyName
{
   my $dfno = $_[0];
   my @inArray = ();

   open FILE, "$dfCopyFile";
   @inArray = <FILE>;
   close FILE;

   foreach my $x (@inArray)
   {
      if ($x =~ /(.*):::(.*)/)
      {
         if ($1 == $dfno)
         {
            my $dfName = $2;
            chomp($dfName);
            Trim($dfName);
            return $dfName;
         }
      }
   }
}

sub createRecCmd
{
   my $file = $recFile;
   my @inFilArray = ();
   my $platName = '';

   open FILE, "$file" or Die ("createRecCmd:Unable to read file $file");
   @inFilArray = <FILE>;
   close FILE;
   my $resFile;

   my $tsn;
   my $fixedSql;
   my $pid = 0;
   my $i = 0;
   my $parent = 0;
   my $count = 0;
   my $ckpScn;

   my (@dfCopyArray, @dfFailedArray);

   open FILE, "$dfCopyFile";
   @dfCopyArray = <FILE>;
   close FILE;

   open FILE, "$failedDf";
   @dfFailedArray = <FILE>;
   close FILE;

   foreach my $x (@inFilArray)
   {
      my ($platid, $fno, $bkpSetName, $bsKey, $doRecv);
      debug4($x);
      if ($x =~ m/\#.*/)
      {
         next;
      }
      if ($x =~ m/(.*?),(.*?),(.*?),(.*?),(.*?),(.*)/)
      {
         $platid = $2;
         $fno = $1;
         $bkpSetName = $3;
         $ckpScn = $4;
         $bsKey = $5;
         $doRecv = $6;

         if (scalar(@dfFailedArray) > 0)
         {
            if (!checkEleRecDfnoExists(\@dfFailedArray, $fno))
            {
               debug3Message("File $fno already rrecovered");
               next;
            }
         }

         if ($doRecv != 1)
         {
            PrintMessage("No incremental backup found for $fno, $doRecv");
            next;
         }

         if ($platName eq '')
         {
            $platName = getPlatName($platid);
         }

         my $bkpSetNameTemp = $bkpSetName;
         $bkpSetNameTemp =~ s/\$//g;
         $resFile = "$tmpMisc/res_".$fno."_".$bkpSetNameTemp.".txt";
         my $dfCopyName = getDFCopyName($fno);

         open FILE, ">$resFile";
         print FILE "run {\n".
                    "allocate channel c1 device type sbt parms ".
                    "$props{'sbtlibparms'};\n".
                    "recover from platform \'$platName\' foreign datafilecopy ".
                    " \'$dfCopyName\' from backupset \'$bkpSetName\';\n".
                    "release channel c1;\n".
                    "}\n";
         close FILE;
      }

      if ($rollParallel)
      {
         ChecktoProceed($rollParallel);

         $pid = fork();

         if ($pid == 0)
         {
            my $count = 0;

            while ($count < 10)
            {
               debug3Message("Recovering $fno using cmdfile ".
                             "$resFile, try# $count");
               my $rman_ra_args =
                  $rman_ra_args1." ".$rman_ra_args2;
               my @resSysArray = RunRMANCmd($rman_ra_args, $resFile);
               my $retCount = scalar @resSysArray;
               debug3Message ("Recover $fno returned $retCount");
               if ($retCount != 0)
               {
                  updateRecoverDFCopy(@resSysArray);
                  exit (0);
               }
               $count = $count + 1;
            }
            open FILE, ">$failedDf";
            print FILE $x."\n";
            close FILE;
         }
         else
         {
            UpdateForkArray ($pid, $rollParallel);
         }
      }
      else
      {
         print "Restorex $resFile\n";
         sleep (10);
      }
   }

   while((my $pid = wait()) > 0)
   {
      #sleep (1);
   }

   PrintMessage ("End of restore/recover phase");
}

sub createResCmd
{
   my $file = $_[0];
   my @inFilArray = ();
   my $platName = '';

   $file = $resFile;

   open FILE, "$file" or Die ("Unable to open $file");
   @inFilArray = <FILE>;
   close FILE;
   my $resCmdFile;

   my $tsn;
   my $fixedSql;
   my $pid = 0;
   my $i = 0;
   my $parent = 0;
   my $count = 0;
   my $ckpScn;
   my (@dfCopyArray, @dfFailedArray);

   open FILE, "$dfCopyFile";
   @dfCopyArray = <FILE>;
   close FILE;

   open FILE, "$failedDf";
   @dfFailedArray = <FILE>;
   close FILE;

   foreach my $x (@inFilArray)
   {
      my ($platid, $fno, $bkpSetName, $bsKey);
      if ($x =~ m/(.*?),(.*?),(.*?),(.*?),(.*)/)
      {
         $platid = $2;
         $fno = $1;
         $bkpSetName = $3;
         $ckpScn = $4;
         $bsKey = $5;

         if (checkEleDfnoExists(\@dfCopyArray, $fno))
         {
            debug3Message ("File $fno already restored");
            next;
         }

         if ($platName eq '')
         {
            $platName = getPlatName($platid);
         }
         my $bkpSetNameTemp = $bkpSetName;
         $bkpSetNameTemp =~ s/\$//g;
         $resCmdFile = "$tmpMisc/res_".$fno."_".$bkpSetNameTemp.".txt";
         open FILE, ">$resCmdFile";
         print FILE "run {\n".
                    "allocate channel c1 device type sbt parms ".
                    "$props{'sbtlibparms'};\n".
                    "restore from platform \'$platName\' foreign datafile ".
                    "$fno format 'X%u' from backupset \'$bkpSetName\';\n".
                    "release channel c1;\n".
                    "}\n";
         close FILE;
      }

      if ($rollParallel)
      {
         ChecktoProceed($rollParallel);

         $pid = fork();

         if ($pid == 0)
         {
            my $count = 0;
            while ($count < 10)
            {
               debug3Message("Restoring $fno using cmdfile ".
                             "$resCmdFile, try# $count");
               my $rman_ra_args =
                  $rman_ra_args1." ".$rman_ra_args2;
               my @resSysArray = RunRMANCmd($rman_ra_args, $resCmdFile);
               my $retCount = scalar @resSysArray;
               debug3Message ("Restore $fno returned $retCount");
               if ($retCount != 0)
               {
                  updateRecoverDFCopy(@resSysArray);
                  exit (0);
               }
               $count = $count + 1;
            }
            open FILE, ">$failedDf";
            print FILE $x."\n";
            close FILE;
         }
         else
         {
            UpdateForkArray ($pid, $rollParallel);
         }
      }
      else
      {
         print "Restorex $resCmdFile\n";
         sleep (10);
      }
   }

   while((my $pid = wait()) > 0)
   {
      #sleep (1);
   }

   PrintMessage ("End of restore/recover phase");
}

sub getDBID
{
   my $sqlplus_sys_cmd = "<<EOF
set line 2000
set serveroutput on
set echo on
set heading off
    SELECT 'dbuniqname='||DB_UNIQUE_NAME
      FROM v\\\$database;
quit
EOF\n";

   my @resSysArray = RunSQLCmd($sqlplus_sys_args, $sqlplus_sys_cmd);
   my $dbUname;

   foreach my $x (@resSysArray)
   {
      if ($x =~ m/dbuniqname=(.*)/)
      {
         $dbUname = $1;
         chomp($dbUname);
         Trim($dbUname);
         $dbUname = uc($dbUname);
      }
   }

   my $sqlplus_ra_cmd = "<<EOF
set line 2000
set serveroutput on
set echo on
set heading off
SELECT 'dbkey='||db_key
  FROM node
 WHERE upper(db_unique_name) = '$dbUname';
quit
EOF\n";
   my @resRaArray = RunSQLCmd($sqlplus_ra_args, $sqlplus_ra_cmd);
   foreach my $x (@resRaArray)
   {
      if ($x =~ m/dbkey=(.*)/)
      {
         $dbId = $1;
         chomp($dbId);
         Trim($dbId);
      }
   }
}

sub performSetupRestore
{
   PrintMessage ("Setting up files for restore");
   Unlink($resFile, 1);
   Unlink($recFile, 1);

   getDBID();

   my $usertsname = $props{'ttsnames'};
   my $sqlplus_sys_cmd = "<<EOF
set line 2000
set serveroutput on
set echo on
set heading off
col name format a40
col dfno format a20
col ckpno format a40
col crpno format a40
    SELECT 'name='||name name
         , 'dfile='||file# dfno
         , 'crp='||CREATION_CHANGE# crpno
      FROM (
           SELECT /*+
                    LEADING(t.x\\\$kccts)
                    USE_HASH(d.df)
                    FULL(t.x\\\$kccts)
                    FULL(d.df)
                    USE_HASH(d.fe)
                    USE_HASH(d.fn)
                    USE_HASH(d.fh)
                    LEADING(d.fe d.fn d.fh)
                  */
                  ROW_NUMBER()
                  OVER (
                    PARTITION BY d.ts# ORDER BY file#
                  ) rn
                , MIN(
                    CASE
                      WHEN enabled = 'READ WRITE'
                       AND status = 'ONLINE'
                      THEN d.ts#
                      ELSE -d.ts#
                    END
                  ) OVER (
                     PARTITION BY d.ts#
                  ) ts#
                , t.name
                , REGEXP_REPLACE(d.name, '(.*)/(.*)', '\\1') dname
                , REGEXP_REPLACE(d.name, '(.*)/(.*)', '\\2') fname
                , file#
                , MIN(checkpoint_change#)
                  OVER (
                    PARTITION BY d.ts#
                  ) checkpoint_change#
                , CREATION_CHANGE#
                , creation_time
             FROM gv\\\$datafile d
                , v\\\$tablespace t
            WHERE d.ts# = t.ts#
              AND d.inst_id = USERENV('INSTANCE')
              AND t.name IN ($usertsname)
          ) df
     ORDER BY ts#;
quit
EOF\n";

   my @resSysArray = RunSQLCmd($sqlplus_sys_args, $sqlplus_sys_cmd);
   my ($tbsHash, @filArray) = GetDFList(@resSysArray);
   my $filStr = join(',', @filArray);
   my $filStrC = scalar(@filArray);
   debug4 "List of $filStrC files:$filStr\n";
   PrintDfList($tbsHash);

   my $sqlplus_ra_cmd = "<<EOF
set line 2000
set serveroutput on
set echo on
set heading off
COLUMN handle FORMAT A40
SELECT 'handle='||handle handle,
       'file='||vb.file# fno,
       'ckp_scn='||bdf.CKP_SCN,
       'bskey='||bdf.bs_key
  from bp
     , bs
     , (select v.file#, max(bp_key) bp_key
          from vbdf v
             , bp p
             , bs s
             , bdf d
         where p.db_key = $dbId
           and p.bs_key = s.bs_key
           and p.status = 'A'
           and s.bs_key = d.bs_key
           and d.file# in ($filStr)
           and v.db_key = $dbId
           AND v.file# = d.file#
           AND v.ckp_scn = d.ckp_scn
           AND v.dbinc_key = d.dbinc_key
           AND v.file# IN ($filStr)
           and p.vb_key is not null
           AND v.vb_key = p.vb_key
           AND d.bs_key = p.bs_key
           AND p.status = 'A'
        group by v.file#
        ) vb
     , bdf
 WHERE bp.bs_key = bs.bs_key
   AND bs.incr_level = 0
   AND bp.bp_key = vb.bp_key
   AND bdf.bs_key = bp.bs_key
   AND bdf.file# IN ($filStr);
quit
EOF\n";
   my @resRaArray = RunSQLCmd($sqlplus_ra_args, $sqlplus_ra_cmd);

   CreateResRecInpFile(\@resRaArray, \@filArray, $filStrC);
   PrintMessage ("Copy $resFile to target tmpdir");
}

sub performSetupRecover
{
   PrintMessage ("Setting up files for recover");
   creUpdRecFile();
   PrintMessage ("$recFile created");
}

sub performRestore
{
   #Unlink($dfCopyFile);
   createResCmd();
}

sub performRecover
{
   createRecCmd();
}

sub Main
{
   parseArg();
   parseProperties();

   if ($context->{"setuprestore"})
   {
      performSetupRestore();
   }
   elsif ($context->{"setuprecover"})
   {
      performSetupRecover();
   }
   elsif ($context->{"restore"})
   {
      performRestore();
   }
   elsif ($context->{"recover"})
   {
      performRecover();
   }
   else
   {
      PrintMessage("Need to add");
   }
}

sub GetTimeStamp
{
   my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
   my @days = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
   my $timeStamp = $months[$mon].$mday."_".$days[$wday];
   $timeStamp = $timeStamp."_".strLPad($hour,2)."_".strLPad($min,2)."_".
                strLPad($sec,2)."_".int(rand(1000));

   return ($timeStamp);
}

###############################################################################
# Function : strLPad
# Purpose  : Pads a string on the left end to a specified length with a
#            specified character and returns the result.  Default pad char is
#            0.
###############################################################################
sub strLPad
{
   my($str, $len) = @_;
   my $chr = "0";

   return substr(($chr x $len) . $str, -1 * $len, $len);
}

###############################################################################
# Function : strRpad
# Purpose  : Pads a string on the right end to a specified length with a
#            specified character and returns the result.  Default pad char is
#            0.
###############################################################################
sub strRpad
{
   my($str, $len) = @_;
   my $chr = "0";

   return substr($str . ($chr x $len), 0, $len);
}

Main();
