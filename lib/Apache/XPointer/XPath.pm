# $Id: XPath.pm,v 1.7 2004/11/13 23:30:02 asc Exp $
use strict;

package Apache::XPointer::XPath;
use base qw (Apache::XPointer);

$Apache::XPointer::XPath::VERSION = '1.0';

=head1 NAME

Apache::XPointer::XPath - mod_perl handler to address XML fragments using XPath.

=head1 SYNOPSIS

 <Directory /foo/bar>

  <FilesMatch "\.xml$">
   SetHandler	perl-script
   PerlHandler	Apache::XPointer::XPath

   PerlSetVar   XPointerSendRangeAs  "XML"
  </FilesMatch>

 </Directory>

 #

 my $ua  = LWP::UserAgent->new();
 my $req = HTTP::Request->new(GET => "http://example.com/foo/bar/baz.xml");
 $req->header("Range" => qq(xmlns("x=x-urn:example")xpointer(*//x:thingy)));

 my $res = $ua->request($req);

=head1 DESCRIPTION

Apache::XPointer is a mod_perl handler to address XML fragments using
the HTTP 1.1 I<Range> header and the XPath scheme, as described in the
paper : I<A Semantic Web Resource Protocol: XPointer and HTTP>.

Additionally, the handler may also be configured to recognize a conventional
CGI parameter as a valid range identifier.

If no 'range' property is found, then the original document is
sent unaltered.

=head1 OPTIONS

=head2 XPointerAllowCGIRange

If set to B<On> then the handler will check the CGI parameters sent with the
request for an argument defining an XPath range.

CGI parameters are checked only if no HTTP Range header is present.

Case insensitive.

=head2 XPointerCGIRangeParam

The name of the CGI parameter to check for an XPath range.

Default is B<range>

=head2 XPointerSendRangeAs

=over 4

=item * B<multi-part>

Returns matches as type I<multipart/mixed> :

 --match
 Content-type: text/xml; charset=UTF-8

 <foo xmlns="x-urn:example:foo" xmlns:baz="x-urn:example:baz">
  <baz:bar>hello</baz:bar>
 </foo>

 --match
 Content-type: text/xml; charset=UTF-8

 <foo xmlns="x-urn:example:foo" xmlns:baz="x-urn:example:baz">
  <baz:bar>world</baz:bar>
 </foo>

 --match--

=item * B<XML>

Return matches as type I<application/xml> :

 <xp:range xmlns:xp="x-urn:cpan:ascope:apache-xpointer#"
           xmlns:default="x-urn:example.com">
  <xp:match>

   <default:foo>
    <default:bar>hello</default:bar>
   </default:foo>

  </xp:match>
  <xp:match>

   <default:foo>
    <default:bar>world</default:bar>
   </default:foo>

  </xp:match>
 </xp:range>

=back

Default is B<XML>; case-insensitive.

=head1 MOD_PERL COMPATIBILITY

This handler will work with both mod_perl 1.x and mod_perl 2.x; it
works better in 1.x because it supports Apache::Request which does
a better job of parsing CGI parameters.

=cut

use XML::LibXML;
use XML::LibXML::XPathContext;

sub parse_range {
    my $pkg    = shift;
    my $apache = shift;
    my $range  = shift;

    my %ns      = ();
    my $pointer = undef;

    $range =~ s/^\s+//;
    $range =~ s/\s+$//;

    # FIX ME - hooks to deal with '^' escaped
    # parens per the XPointer spec

    while ($range =~ /\G\s*xmlns\(([^=]+)=([^\)]+)\)/mg) {
	$ns{ $1 } = $2;
    }
    
    $range =~ /xpointer\((.*)\)$/;
    $pointer = $1;
    
    return (\%ns,$pointer);
}

sub range {
    my $pkg     = shift;
    my $apache  = shift;
    my $ns      = shift;
    my $pointer = shift;

    my $parser = XML::LibXML->new();
    my $doc    = undef;

    eval {
	$doc = $parser->parse_file($apache->filename());
    };
    
    if ($@) {
	$apache->log()->error(sprintf("failed to parse file '%s', %s",
				      $apache->filename(),$@));

	return {success  => 0,
		response => $pkg->_server_error()};
    }
    
    my $context = XML::LibXML::XPathContext->new($doc);

    foreach my $prefix (keys %$ns) {
	$context->registerNs($prefix,$ns->{$prefix});
    }

    #

    my $result = undef;
    
    eval {
	$result = $context->findnodes($pointer);
    };
    
    if ($@) {
	$apache->log()->error(sprintf("failed to find nodes for '%s', %s",
				      $pointer,$@));

	return {success  => 0,
		response => $pkg->_server_error()};
    }

    #

    return {success  => 1,
	    encoding => $doc->encoding(),
	    result   => $result};
}

sub send_results {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;
    
    if ($apache->dir_config("XPointerSendRangeAs") =~ /^multi-?part$/i) {
	$pkg->send_multipart($apache,$res);
    }
    
    else {
	$pkg->send_xml($apache,$res);
    }

    return 1;
}

sub send_multipart {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;

    $apache->content_type(qq(multipart/mixed; boundary="match"));

    if (! $pkg->_mp2()) {
	$apache->send_http_header();
    }

    #

    foreach my $node ($res->{'result'}->get_nodelist()) {

	# note : $node->toString() does not serialize
	#         namespace information
	#        $node->toStringC14N() results in : $node's
	#         root element from being included (I'm sure
	#         there's magic XPath to deal with this but 
	#         I haven't figured it out yet; mal-formed
	#         XML

	my $root = XML::LibXML::Element->new($node->localname());

	$root->setNamespace($node->namespaceURI(),
			    $node->prefix());

	foreach my $child ($node->childNodes()) {

	    # see also : libxml/tree.h
	    # XML_ELEMENT_NODE= 1

	    if ($child->nodeType() == 1) {
		$root->setNamespace($child->namespaceURI(),
				    $child->prefix());
	    }

	    $root->addChild($child);
	}

	$apache->print(qq(--match\n));
	$apache->print(sprintf("Content-type: text/xml; charset=%s\n\n",$res->{'encoding'}));
	$apache->print($root->toString(1,1));
	$apache->print(qq(\n));
    }

    $apache->print(qq(--match--\n));
    return 1;
}

sub send_xml {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;

    # Note : the document-ness of $doc handles
    #         all the goofy XMLNS hoops we jump
    #         through above

    my $doc = XML::LibXML::Document->new();
    $doc->setEncoding($res->{'encoding'});
    
    my $root = XML::LibXML::Element->new("range");
    $root->setNamespace("x-urn:cpan:ascope:apache-xpointer-xpath#","xp");

    foreach my $node ($res->{'result'}->get_nodelist()) {
	my $item = XML::LibXML::Element->new("xp:match");
	$item->addChild($node);
	$root->addChild($item);
    }

    $doc->setDocumentElement($root);
    
    #

    $pkg->_header_out($apache,"Content-Encoding",$res->{'encoding'});
    $apache->content_type(qq(application/xml));

    if (! $pkg->_mp2()) {
	$apache->send_http_header();
    }

    #

    $apache->print($doc->toString());
    return 1;
}

=head1 VERSION

1.0

=head1 DATE

$Date: 2004/11/13 23:30:02 $

=head1 AUTHOR

Aaron Straup Cope E<lt>ascope@cpan.orgE<gt>

=head1 SEE ALSO

L<Apache::XPointer>

=head1 LICENSE

Copyright (c) 2004 Aaron Straup Cope. All rights reserved.

This is free software, you may use it and distribute it under
the same terms as Perl itself.

=cut 

return 1;
