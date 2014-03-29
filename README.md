Description:  
This is a cross-platform Perl version of the official send_nrdp.py and send_nrdp.sh clients for Nagios NRDP. This plugin uses only the standard Perl libs and should work on any OS; it has however been tested to work on Linux and Windows with active state Perl.  

This plugin was designed to function as close as possible to the original send_nrdp clients.

Download:  
http://roshamboot.org/main/wp-content/uploads/2013/02/perl_nrdp.zip

Known Issues:  
None

Patch Notes:  
v1.2:
- Minor efficiency improvements.
v1.1:
- Fixed un-escaped character issue that prevented script working on some versions of Perl.
 
Usage:  
-u, –url  
The URL used to access the remote NRDP agent. i.e. http://nagiosip/nrdp/ **REQUIRED**  
-t, –token  
The authentication token used to access the remote NRDP agent. **REQUIRED**  
-H, –hostname  
The name of the host associated with the passive host/service check result.
This script will attempt to learn the hostname if not supplied.  
-s, –service  
For service checks, the name of the service associated with the passive check result.  
-S, –state  
The state of the host or service. Valid values are: OK, CRITICAL, WARNING, UNKNOWN  
-o, –output  
Text output to be sent as the passive check result.  
-d, –delim  
Used to set the text field delimiter when using non-XML file input or command-line input.
Defaults to tab (\\t).  
-c, –checktype  
Used to specify active or passive, 0 = active, 1 = passive. Defaults to passive.  
-f, –file  
Use this switch to specify the full path to a file to read. There are two usable formats:  
1. A field-delimited text file, where the delimiter is specified by -d  
2. An XML file in NRDP input format. An example can be found by browsing to the NRDP URL.  
-i, –input  
This switch specifies that you wish to input the check via standard input on the command line.  
-h, –help  
Display this help text. 