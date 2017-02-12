sub https_vcl_recv {
	if (std.port( server.ip ) == 8443 || req.http.X-Forwarded-Proto == "https") {
		set req.http.X-Forwarded-Proto = "https";
		set req.http.https = "on";
	}

    # Redirect to https
	if (client.ip != "127.0.0.1" && req.http.X-Forwarded-Proto !~ "(?i)https" &&
			req.http.host ~ "tutoandco\.colas-delmas\.fr$") {
		set req.http.x-redir = "https://" + req.http.host + req.url;
		return(synth(750, ""));
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
	if (resp.status == 750) {
	 	set resp.http.Location = req.http.x-redir;
	 	set resp.status = 301;
	 	return (deliver);
	}
}