#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use LWP::Simple;
use LWP::UserAgent;
use File::Basename;
use Sys::Hostname;
use XML::Writer;

use constant {
	USER_AGENT => 'perl_nrdp/',
	CLIENT_VERSION => '1.3b150222',
	NRDP_VERSION => '1.5',
};

Getopt::Long::Configure ("bundling");

# Process command line switch input.
sub proc_input {
	my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @_;
	
	my $dataBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
	if (!$strService) {
		$dataBuilder .= generate_host_check_xml($strHostname, $strState, $strOutput, $bCheckType);
	} else {
		$dataBuilder .= generate_service_check_xml($strHostname, $strService, $strState, $strOutput, $bCheckType);
	}
	$dataBuilder .= "</checkresults>";
	return ($dataBuilder, 'XMLDATA');
}

# Process either XML or other formatted file.
sub proc_file {
	my($strFile,$chrDelim) = @_;
	if (-e $strFile) {
		my ($fDir, $fName, $fExt) = fileparse($strFile, qr/\.[^.]*/);
		my $dataBuilder;
		my $dataType;
		my $fileType;
		my $intLineCount = 0;

		if ($fExt =~ m/\.xml$/i) {
			$fileType = 'xml';
			$dataType = 'XMLDATA';
		} elsif ($fExt =~ m/\.json$/i) {
			$fileType = 'json';
			$dataType = 'JSONDATA';
		} else {
			$fileType = 'delimited';
			$dataType = 'XMLDATA';
		}
		open(FILE, '<', $strFile);
		while (<FILE>) {
			if (($fileType eq 'xml') || ($fileType eq 'json')) {
				$dataBuilder .= $_;
			} else {
				if ($intLineCount == 0) {
					$dataBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
				}
				$intLineCount++;
				my $line = $_;
				$line =~ s/^\s+|\s+$//g;
				my @aryLine = split($chrDelim, $line, 6);
				if (scalar(@aryLine) == 4) {
					my($strHostname, $strState, $strOutput, $bCheckType) = @aryLine;
					$dataBuilder .= generate_host_check_xml($strHostname, $strState, $strOutput, $bCheckType);
				} elsif (scalar(@aryLine) == 5) {
					my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @aryLine;
					$dataBuilder .= generate_service_check_xml($strHostname, $strService, $strState, $strOutput, $bCheckType);
				} else {
					print "WARNING - Line $intLineCount is incorrectly formatted, can't parse fields. Continuing...\n";
					next; 
				}
			}
		}
		close(FILE);
		if (($fileType eq 'delimited') && ($intLineCount > 0)) {
			$dataBuilder .= "</checkresults>";
		}
		return ($dataBuilder, $dataType);
	} else {
		print "ERROR - Unable to find the specified file.\n";
		exit 1;
	}
}

# Process input from STDIN.
sub proc_terminal {
	my $chrDelim = $_[0];
	print "Enter check details: \n";
	my $stdRead = <>;
	$stdRead =~ s/^\s+|\s+$//g;
	my @aryInput = split($chrDelim, $stdRead, 6);
	my $dataBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
	if (scalar(@aryInput) == 4) {
        	my($strHostname, $strState, $strOutput, $bCheckType) = @aryInput;
		$dataBuilder .= generate_host_check_xml($strHostname, $strState, $strOutput, $bCheckType);
        } elsif (scalar(@aryInput) == 5) {
		my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @aryInput;
		$dataBuilder .= generate_service_check_xml($strHostname, $strService, $strState, $strOutput, $bCheckType);
        } else {
		print "ERROR - Input is incorrectly formatted, can't parse fields\n";
		help(1);
        }
	$dataBuilder .= "</checkresults>";
    return ($dataBuilder, 'XMLDATA');
}

# Build a single service-check XML element.
sub generate_service_check_xml {
	my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @_;
	my $intState = validate_state($strState);
	validate_checktype($bCheckType);
	my $dataBuilder = '';
	my $writer = new XML::Writer(OUTPUT => \$dataBuilder, NEWLINES => 0);

	$writer->startTag('checkresult', 'type' => 'service', 'checktype' => $bCheckType);
	$writer->dataElement('hostname', $strHostname);
	$writer->dataElement('servicename', $strService);
	$writer->dataElement('state', $intState);
	$writer->dataElement('output', $strOutput);
	$writer->endTag('checkresult');
	$writer->end();

	return $dataBuilder;
}

# Build a single host-check XML element.
sub generate_host_check_xml {
	my($strHostname,  $strState, $strOutput, $bCheckType) = @_;
	my $intState = validate_state($strState);
	validate_checktype($bCheckType);
        my $dataBuilder = '';
        my $writer = new XML::Writer(OUTPUT => \$dataBuilder, NEWLINES => 0);

	$writer->startTag('checkresult', 'type' => 'host', 'checktype' => $bCheckType);
	$writer->dataElement('hostname', $strHostname);
	$writer->dataElement('state', $intState);
	$writer->dataElement('output', $strOutput);
	$writer->endTag('checkresult');
	$writer->end();

	return $dataBuilder;
}

sub validate_state {
	my $strState = $_[0];
	my %hshValidStates = (
                'OK' => 0,
                'WARNING' => 1,
                'CRITICAL' => 2,
                'UNKNOWN' => 3);

	$strState = uc($strState);
	if (! exists $hshValidStates{$strState}) {
		print "ERROR - Invalid state specified.\n";
		help(1);
	}

	return $hshValidStates{$strState};
}

sub validate_checktype {
	my $checkType = $_[0];

	if (($checkType ne '0') && ($checkType ne '1')) {
		print "ERROR - Invalid checktype specified.\n";
		help(1);
	}
	return $checkType;
}

sub post_data {
	my($strURL, $strToken, $postContent, $dataType, $verbose) = @_;
	my $httpAgent = LWP::UserAgent->new;

	$httpAgent->agent(USER_AGENT . CLIENT_VERSION);
	$httpAgent->protocols_allowed(['http', 'https']);
	
	my $httpResponse = $httpAgent->post( $strURL,
	[
		'token' => $strToken,
		'cmd' => 'submitcheck',
		$dataType => $postContent
	],);
	
	if (!$httpResponse->is_success) {
		print "ERROR - NRDP Returned: " . $httpResponse->status_line . " " . $httpResponse->content;
		exit 3;
	}
	my $contentType = $httpResponse->header('Content-Type');
	my ($status, $message) = (0, '');

	# Quick-n-dirty parse for status and message
	if ($contentType =~ m!/json\b!) {
		if ($httpResponse->content =~ m/"status":\s*([0-9-]+)/s) {
			$status = 0 + $1;
		}
		if ($httpResponse->content =~ m/"message":\s*"(.*?)"/s) {
			$message = $1;
		}
	} elsif ($contentType =~ m!/xml\b!) {
		if ($httpResponse->content =~ m!<status>([0-9-]+)</status>!s) {
			$status = 0 + $1;
		}
		if ($httpResponse->content =~ m!<message>(.*?)</message>!s) {
			$message = $1;
		}
	}
	if ($verbose) {
		print "Request:\n$postContent\n";
		print "Response:\n" . $httpResponse->status_line . "\n" . $httpResponse->content . "\n\n";
	}
	if ($status == 0) {
		print "OK\n";
	} else {
		print "ERROR - NRDP Returned: $message\n";
		exit $status;
	}
}

sub help {
	my $exitCode = $_[0] || 0;
	my $strVersion = CLIENT_VERSION;
	my $strNRDPVersion = NRDP_VERSION;
	print "\nPerl NRDP sender version: v$strVersion for NRDP version: $strNRDPVersion\n";
	print "By John Murphy <john.murphy\@roshamboot.org>, GNU GPL License\n";
	print "\nUsage: ./perl_nrdp.pl -u <Nagios NRDP URL> -t <Token> [-H <Hostname> -S <State> -o <Information|Perfdata> [-s <service name> -c <0/1>] | -f <File path> [-d <Field delimiter>] | -i [-d <Field delimiter> ]]\n\n";
	print <<HELP;
-u, --url
	The URL used to access the remote NRDP agent. i.e. http://nagiosip/nrdp/
-t, --token
	The authentication token used to access the remote NRDP agent.
-H, --hostname
	The name of the host associated with the passive host/service check result. 
	This script will attempt to determine the hostname if not supplied.
-s, --service
	For service checks, the name of the service associated with the passive check result.
-S, --state
	The state of the host or service. Valid values are: OK, CRITICAL, WARNING, UNKNOWN
-o, --output
	Text output to be sent as the passive check result.
-d, --delim
	Used to set the text field delimiter when using non-XML file input or command-line input. 
	Defaults to tab (\\t).
-c, --checktype
	Used to specify active or passive, 0 = active, 1 = passive. Defaults to passive.
-f, --file
	Use this switch to specify the full path to a file to read. There are three usable formats:
	1. A field-delimited text file, where the delimiter is specified by -d
	2. An XML file in NRDP input format. An example can be found by browsing to the NRDP API URL.
	3. A JSON file in NRDP input format. An example can be found by browsing to the NRDP API URL.
-i, --input
	This switch specifies that you wish to input the check via standard input on the command line.
-v, --verbose
	This switch enables verbose mode. This writes out the request and response content from HTTP.
-h, --help
	Display this help text.
	
HELP
	exit $exitCode;
}

##############################################
##
## BEGIN MAIN
##
##############################################

# Initialize and read user input
my ($strURL, $strToken, $strHostname, $strService, $strState, $strOutput, $chrDelim, $bCheckType, $strFile, $oHelp, $stdReadTerm, $bVerbose);
$oHelp = undef;
$stdReadTerm = undef;
$chrDelim = undef;

GetOptions("u=s" => \$strURL, 		"url=s" => \$strURL,
           "t=s" => \$strToken, 	"token=s" => \$strToken,
           "H=s" => \$strHostname, 	"hostname=s" => \$strHostname,
           "s=s" => \$strService, 	"service=s" => \$strService,
           "S=s" => \$strState, 	"state=s" => \$strState,
           "o=s" => \$strOutput, 	"output=s" => \$strOutput,
           "d=s" => \$chrDelim, 	"delim=s" => \$chrDelim,
           "c=i" => \$bCheckType, 	"checktype=i" => \$bCheckType,
           "f=s" => \$strFile, 		"file=s" => \$strFile,
           "i" => \$stdReadTerm,	"input" => \$stdReadTerm,
           "v" => \$bVerbose,           "verbose" => \$bVerbose,
           "h" => \$oHelp, 		"help" => \$oHelp) or help(2);

if (defined $oHelp) {
	help();
}

if (!defined $strURL || !defined $strToken) {
	print "You must set a URL and Token.\n";
	help(2);
}

# Ensure URL ends with a trailing / character
$strURL =~ s!/?$!/!;

# Can't accept newline chars as a delimiter and escape punctuation chars so regex doesn't interpret them literally.
if (!defined $chrDelim) {
	$chrDelim = "\t";
} elsif ($chrDelim =~ m/\r|\n/) {
	print "Can't use new line character as a field separator.\n";
	help(2);
} elsif ($chrDelim =~ m/^[[:punct:]]{1}$/) {
	$chrDelim = "\\" . $chrDelim;
}

if (!defined $bCheckType) {
	$bCheckType = 1;
}

if (!defined $strHostname) {
	$strHostname = hostname() or die "Unable to determine hostname, please enter manually";
}

# Depending on user options build the XML doc to post.
my ($postContent, $dataType);
if (defined $strFile) {
	($postContent, $dataType) = proc_file($strFile, $chrDelim);
} elsif (defined $stdReadTerm) {
	($postContent, $dataType) = proc_terminal($chrDelim);
} elsif ((defined $strHostname) && (defined $strState) && (defined $strOutput)) {
	($postContent, $dataType) = proc_input($strHostname, $strService, $strState, $strOutput, $bCheckType);
} else {
	print "Incorrect options set.\n";
	help(2);
}

# Post data via NRDP API to Nagios.
if (defined $postContent) {
	post_data($strURL, $strToken, $postContent, $dataType, $bVerbose);
} elsif ($bVerbose) {
	print "INFO - No data to send, exiting normally.\n";
}
exit 0;
