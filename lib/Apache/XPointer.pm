# $Id: XPointer.pm,v 1.10 2004/11/13 21:13:40 asc Exp $
use strict;

package Apache::XPointer;

$Apache::XPointer::VERSION = '1.0';

=head1 NAME

Apache::XPointer - mod_perl handler to address XML fragments.

=head1 SYNOPSIS

 <Directory /foo/bar>

  <FilesMatch "\.xml$">
   SetHandler	perl-script
   PerlHandler	Apache::XPointer::XPath
  </FilesMatch>

 </Directory>

 #

 my $ua  = LWP::UserAgent->new();
 my $req = HTTP::Request->new(GET => "http://example.com/foo/bar/baz.xml");
 $req->header("Range" => qq(xmlns("x=x-urn:example")xpointer(*//x:thingy)));

 my $res = $ua->request($req);

=head1 DESCRIPTION

Apache::XPointer is a mod_perl handler to address XML fragments using
the HTTP 1.1 I<Range> header, as described in the paper : I<A Semantic
Web Resource Protocol: XPointer and HTTP>.

Additionally, the handler may also be configured to recognize a conventional
CGI parameter as a valid range identifier.

If no 'range' property is found, then the original document is
sent unaltered.

=head1 IMPORTANT

This package is a base class and not expected to be invoked
directly. Please use one of the scheme-specific handlers instead.

=head1 SUPPPORTED SCHEMES

=head2 XPath

Consult L<Apache::XPointer::XPath>

=head1 MOD_PERL COMPATIBILITY

This handler will work with both mod_perl 1.x and mod_perl 2.x; it
works better in 1.x because it supports Apache::Request which does
a better job of parsing CGI parameters.

=cut

require 5.6.0;
use mod_perl;

use constant MP2 => ($mod_perl::VERSION >= 1.99) ? 1 : 0;

BEGIN {

     if (MP2) {
         require Apache2;
         require Apache::RequestRec;
         require Apache::RequestIO;
         require Apache::RequestUtil;
         require Apache::Const;
         require Apache::Log;
         require Apache::URI;
         require APR::Table;
         require APR::URI;
         Apache::Const->import(-compile => qw(OK DECLINED HTTP_NOT_FOUND HTTP_INTERNAL_SERVER_ERROR));
      }

     else {
         require Apache;
         require Apache::Constants;
         require Apache::Log;
         require Apache::Request;
         Apache::Constants->import(qw(OK DECLINED NOT_FOUND SERVER_ERROR));
     }
}

sub handler : method {
  my $pkg    = shift;
  my $apache = shift;

  my $range = $pkg->_header_in($apache,"Range");

  if ((! $range) && ($apache->dir_config("XPointerAllowCGIRange") =~ /^on$/i)) {
      my $rparam  = $apache->dir_config("XPointerCGIRangeParam") || "range";

      # Waiting for Apache::Request to be ported
      # to mod_perl2 because default query parser
      # doesn't do a very good job of handling stuff
      # like range=xmlns(foo=x-urn:bar)

      if ($pkg->_mp2()) {
	  $apache->parsed_uri()->query() =~ /^$rparam=(.*)$/;
	  $range = $1;
      }

      else {
	  my $request = Apache::Request->new($apache);
	  $range = $request->param($rparam);
      }
  }

  if (! $range) {
      return $pkg->_declined();
  }

  #

  my ($ns,$pointer) = $pkg->parse_range($apache,$range);

  if (! $pointer) {
      $apache->log()->error(sprintf("failed to parse range '%s'",
				    $range));
      
      return $pkg->_server_error();
  }

  #

  my $res = $pkg->range($apache,$ns,$pointer);

  if ((! $res) || (! $res->{success})) {
      return $res->{response};
  }

  $pkg->send_results($apache,$res);
  return $pkg->_ok();
}

sub parse_range {
    my $pkg = shift;
    return $pkg->_nometh(@_);
}

sub range {
    my $pkg = shift;
    return $pkg->_nometh(@_);
}

sub send_results {
    my $pkg    = shift;
    return $pkg->_nometh(@_);
}

sub _mp2 {
    return MP2;
}

sub _nometh {
    my $pkg    = shift;
    my $apache = shift;

    my $caller = (caller(1))[3];
    $caller =~ s/.*:://;

    $apache->log()->error(sprintf("package %s does not define a '%s' method",
				  $pkg,$caller));
    return 0;
}

sub _declined {
    my $pkg = shift;
    return ($pkg->_mp2()) ? Apache::DECLINED() : Apache::Constants::DECLINED();
}

sub _server_error {
    my $pkg = shift;
    return ($pkg->_mp2()) ? Apache::HTTP_INTERNAL_SERVER_ERROR() : Apache::Constants::SERVER_ERROR();
}

sub _not_found {
    my $pkg = shift;
    return ($pkg->_mp2()) ? Apache::HTTP_NOT_FOUND() : Apache::Constants::NOT_FOUND();
}

sub _ok {
    my $pkg = shift;
    return ($pkg->_mp2()) ? Apache::OK() : Apache::Constants::OK();
}

sub _header_in {
    my $pkg    = shift;
    my $apache = shift;
    my $field  = shift;

    return ($pkg->_mp2()) ? $apache->headers_in()->{$field} : $apache->header_in($field);
}

sub _header_out {
    my $pkg    = shift;
    my $apache = shift;
    my $field  = shift;
    my $value  = shift;

    ($pkg->_mp2()) ? $apache->headers_out()->{$field} = $value: $apache->header_out($field,$value);
}

=head1 VERSION

1.0

=head1 DATE

$Date: 2004/11/13 21:13:40 $

=head1 AUTHOR

Aaron Straup Cope E<lt>ascope@cpan.orgE<gt>

=head1 SEE ALSO

http://www.mindswap.org/papers/swrp-iswc04.pdf

http://www.w3.org/TR/WD-xptr

=head1 LICENSE

Copyright (c) 2004 Aaron Straup Cope. All rights reserved.

This is free software, you may use it and distribute it under
the same terms as Perl itself.

=cut

return 1;
