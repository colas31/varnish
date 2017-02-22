sub https_vcl_recv {
	if (std.port( server.ip ) == 443
		|| std.port( server.ip ) == 9443
		|| req.http.X-Forwarded-Proto == "https") {
		set req.http.X-Forwarded-Proto = "https";
		set req.http.https = "on";
	}

    # https://info.varnish-software.com/blog/rewriting-urls-with-varnish-redirection
	if (client.ip != "127.0.0.1"
	        && req.http.X-Forwarded-Proto !~ "(?i)https" &&
			 req.http.host ~ "tutoandco\.colas-delmas\.fr$") {

		set req.http.location = "https://" + req.http.host + req.url;
		return(synth(301));
	}

}

#
# to cache HTTP and HTTPS requests separately and avoid redirection loops
#
sub https_vcl_hash {
	if ( req.http.X-Forwarded-Proto ) {
		hash_data( req.http.X-Forwarded-Proto );
	}
}

sub https_vcl_synth {
	if (resp.status == 301 || resp.status == 302) {
	 	set resp.http.Location = req.http.location;
	 	return (deliver);
	}
}