#-e This is a basic VCL configuration file for varnish.  See the vcl(7)
# https://www.varnish-cache.org/docs/4.1/users-guide/vcl-built-in-subs.html
# https://www.varnish-software.com/book/4.0/chapters/VCL_Basics.html#vcl-built-in-functions-and-keywords
# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.

# https://www.varnish-software.com/wiki/content/tutorials/varnish/sample_vclTemplate.html
vcl 4.0;


import directors;
import std;
include "/etc/varnish/backend.vcl";
include "/etc/varnish/mobiledetect.vcl";

#include "/etc/varnish/devicedetect.vcl";
include "/etc/varnish/ban_purge.vcl";
include "/etc/varnish/wordpress.vcl";
include "/etc/varnish/static_files.vcl";
include "/etc/varnish/bypass.vcl";
include "/etc/varnish/https.vcl";

sub vcl_init {
	new vdir1 = directors.round_robin();
	vdir1.add_backend(backend1);
}


#
# This function is used when a request is send by a HTTP client (Browser)
#
sub vcl_recv {
	# We detect mobiles devices or not (include mobiledetect.vcl) and normalize the User-Agent Http Header
	call mobiledetect;

 	set req.http.Via = "1.1 varnish-v4";
	set req.http.grace = "none";

	call https_vcl_recv;
	call ban_purge_vcl_recv;

    # Normalize the header, remove the port (in case you're testing this on various TCP ports)
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");
    # Remove the proxy header (see https://httpoxy.org/#mitigate-varnish)
    unset req.http.proxy;
    # Normalize the query arguments
    set req.url = std.querysort(req.url);

	if ( req.http.host ~ "tutoandco\.colas-delmas\.fr$") {
		# send all traffic to the vdir director
		set req.backend_hint = vdir.backend();
	} else {
		return(pipe);
	}

	# Added security, the "w00tw00t" attacks are pretty annoying so lets block it before it reaches our webserver
	if (req.url ~ "^/w00tw00t"){
		return( synth(403, "not permitted !"));
	}

	# Only deal with "normal" types
	if (req.method != "GET" &&
			req.method != "HEAD" &&
			req.method != "PUT" &&
			req.method != "POST" &&
			req.method != "TRACE" &&
			req.method != "OPTIONS" &&
			req.method != "PATCH" &&
			req.method != "DELETE") {
		/* Non-RFC2616 or CONNECT which is weird. */
		return (pipe);
	}

	call bypass_varnish_cookies;
	call bypass_varnish_urls;
	call wordpress_vcl_recv;
    call cookies_vcl_recv;


	# Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
	if (req.method != "GET" && req.method != "HEAD") {
		return (pass);
	}

	# Don't cache HTTP authentication
	if (req.http.Authorization) {
		return (pass);
	}

	# Normalize Accept-Encoding header
	# straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
	if (req.http.Accept-Encoding) {
		if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
			# No point in compressing these
			unset req.http.Accept-Encoding;
		} elsif (req.http.Accept-Encoding ~ "gzip") {
			set req.http.Accept-Encoding = "gzip";
		} elsif (req.http.Accept-Encoding ~ "deflate") {
			set req.http.Accept-Encoding = "deflate";
		} else {
			# unkown algorithm
			unset req.http.Accept-Encoding;
		}
	}

	call static_files_vcl_recv;

	# Cache all others requests
	return (hash);
}

#
# Called after vcl_recv to create a hash value for the request.
# This is used as a key to look up the object in Varnish.
#
sub vcl_hash {

	hash_data(req.url);

	if (req.http.host) {
		hash_data(req.http.host);
	} else {
		hash_data(server.ip);
	}

	call https_vcl_hash;
}

#
#
#
sub vcl_hit {
	# Trace vcl_call

	# Called when a cache lookup is successful.
	if (obj.ttl >= 0s) {    # normal hit
		return (deliver);
	}
	# We have no fresh fish. Lets look at the stale ones.
	if (std.healthy(req.backend_hint)) {
		# Backend is healthy. Limit age to 10s.
		if (obj.ttl + obj.grace > 0s) {
			set req.http.grace = "normal(limited)";
			return (deliver);
		} else {
			# No candidate for grace. Fetch a fresh object.
			return(fetch);
		}
	} else {
		# backend is sick - use full grace
		if (obj.ttl + obj.grace > 0s) {
			# Object is in grace, deliver it
			# Automatically triggers a background fetch
			set req.http.grace = "full";
			return (deliver);
		} else {
			# no graced object.
			return (fetch);
		}
	}

	# fetch & deliver once we get the result
	return (fetch); # Dead code, keep as a safeguard
}

#
# Called after a cache lookup if the requested document was not found in the cache.
# Its purpose is to decide whether or not to attempt to retrieve the document from the backend, and which backend to use.
#
sub vcl_miss {
	return (fetch);
}

#
#
#
sub vcl_pass {

}

#
# Called before sending the backend request.
# In this subroutine you typically alter the request before it gets to the backend.
#
sub vcl_backend_fetch {

}

#
# The response specifically served from a backend to varnishd.
# Called after the response headers has been successfully retrieved from the backend.
# on previous version function called vcl_fetch
#
sub vcl_backend_response {
	if ( beresp.http.Content-Length == "0"
			&& bereq.retries < 3
			&& beresp.status != 301
			&& beresp.status != 302
			&& beresp.status != 404 ) {
		return(retry);
	}

	# Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
	# This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
	# A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
	# This may need finetuning on your setup.
	#
	# To prevent accidental replace, we only filter the 301/302 redirects for now.
	if (beresp.status == 301
		|| beresp.status == 302) {
		set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
	}


    # Default
    set beresp.keep = 1m;

	# beresp.ttl is initialized with the first value it finds among:
	# The s-maxage variable in the Cache-Control response header field
	# The max-age variable in the Cache-Control response header field
	# The Expires response header field
	# The default_ttl parameter.
	if (!beresp.http.ttl) {
		set beresp.ttl = 1w;
	}

	# Grace to allow varnish to serve content if backend is sick
	# Tells varnish to keep objects 24 hour in cache past their TTL
	if (beresp.http.Cache-Control ~ "stale-while-revalidate\s*=\s*\d+") {
        set beresp.grace
            = std.duration(regsub(beresp.http.Cache-Control,
                                 "^.*stale-while-revalidate\s*=\s*(\d+).*$",
                                 "\1s"), 120s);
    } else {
        set beresp.grace = 24h ;
    }

	set beresp.http.X-original-status= beresp.status;
	set beresp.http.X-TTL = beresp.ttl;

	call wordpress_vcl_backend_response;

	if (beresp.status == 301
		|| beresp.status == 404) {
		set beresp.ttl = 52w;
		set beresp.uncacheable = false;
		return (deliver);
	}

	if (beresp.ttl <= 0s
		|| beresp.status == 307
		|| beresp.http.Set-Cookie
		|| beresp.http.Surrogate-control ~ "no-store"
		|| beresp.http.Cache-Control ~ "no-cache|no-store|private"
		|| beresp.http.Vary == "*") {
		/*
		 * Mark as "Hit-For-Pass" for the next 2 minutes
		 */
		set beresp.ttl = 120s;
		set beresp.uncacheable = true;
		return (deliver);
	}

	call static_files_vcl_backend_response;

	return (deliver);
}

#
# Called before a cached object is delivered to the client.
# The routine when we deliver the HTTP request to the user
# Last chance to modify headers that are sent to the client
#
sub vcl_deliver {
	# Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
	# and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
	# So take hits with a grain of salt
	set resp.http.X-Cache-Hits = obj.hits;

	set resp.http.X-Served-By = server.identity;
	if (obj.hits > 0) {
		set resp.http.X-Server = "Apache HIT";
		set resp.http.X-Cache-Hits = obj.hits;
	} else {
		set resp.http.X-Server = "Apache MISS : ";
	}

	# Deliver the object to the client.
	return (deliver);
}



#
#
#
sub vcl_synth {
	call https_vcl_synth;

	# Custom response code from return(synth)
	if ( resp.status == 202
		|| resp.status == 403 ) {
		synthetic(resp.reason);
		set resp.status = 202;
	} else {
		set resp.http.Content-Type = "text/html; charset=utf-8";
		set resp.http.Retry-After = "5";

		synthetic( {"<?xml version='1.0' encoding='utf-8'?>
					<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Strict//EN' 'http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd'>
						<html>
							<head>
								<title>"} + resp.status +" "+ resp.reason + {"</title>
							</head>
							<body>
								<br/>
								<h1>Error "} + resp.status + " " + resp.reason + {"</h1>
								<p>No backend healthy</p>
								<h3>Guru Meditation:</h3>
								<p>XID: "} + req.xid + {"</p>
								<p>Retries: "} + req.restarts + {"</p>
								<hr>
							</body>
						</html>"} );
	}
	return (deliver);
}

#
# This subroutine is called if we fail the backend fetch.
#
sub vcl_backend_error {
	# If backend fetch failed try the request on an other backend
	if ( beresp.status == 503
		&& bereq.retries < 3
		&& bereq.method == "GET" ) {
		# jumps back up to vcl_backend_fetch
		return(retry);
	}

	set beresp.http.Content-Type = "text/html; charset=utf-8";
	set beresp.http.Retry-After = "5";


	synthetic( {"<?xml version='1.0' encoding='utf-8'?>
				<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
									<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="fr" lang="fr">
					<head>
						<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
						<meta name="viewport" content="" />
						<meta name="robots" content="noindex, nofollow" />
						<title>Site indisponible (503)</title>
					</head>
					<body style="text-align:center;width: 1000px;margin: 0 auto;">
						<br/>
						<h1>Site indisponible (503)</h1>
						<div id="info_message">
							<strong>
								Merci de rééssayer plus tard.
							</strong>
							<p>"} + beresp.status + " : " + beresp.reason + {"
								<br />
								No backend healthy
							</p>
							<h3>Guru Meditation:</h3>
							<p>XID: "} + bereq.xid + {"</p>
							<div style="text-align:left;margin: 0 auto;width: 310px;">
								<div><b>Time:</b> "} + now + {"</div>
								<div><b>Url:</b> "} + bereq.http.host + bereq.url + {"</div>
								<div><b>Method:</b> "} + bereq.method + {"</div>
								<div><b>Content-Length:</b> "} + beresp.http.Content-Length + {"</div>
								<div><b>User-Agent:</b> "} + bereq.http.User-Agent + {"</div>
								<div><b>Cookies:</b> "} + bereq.http.cookie + {"</div>

								<div><b>X-Served-By:</b> "} + server.identity + {"</div>
								<div><b>Backend:</b> "} + beresp.backend.name + {"</div>
								<div><b>Backend:</b> "} + bereq.backend + {"</div>

								<div><b>Retries:</b> "} + bereq.retries + {"</div>
								<div><b>Age:</b> "} + bereq.http.Age + {"</div>
							</div>
						</div>
						<hr>
					</body>
				</html>"} );
	return(deliver);
}

sub vcl_pipe {
	# Called upon entering pipe mode.
	# In this mode, the request is passed on to the backend, and any further data from both the client
	# and backend is passed on unaltered until either end closes the connection. Basically, Varnish will
	# degrade into a simple TCP proxy, shuffling bytes back and forth. For a connection in pipe mode,
	# no other VCL subroutine will ever get called after vcl_pipe.

	# Note that only the first request to the backend will have
	# X-Forwarded-For set.  If you use X-Forwarded-For and want to
	# have it set for all requests, make sure to have:
	# set bereq.http.connection = "close";
	# here.  It is not set by default as it might break some broken web
	# applications, like IIS with NTLM authentication.

	set bereq.http.connection = "Close";

	# Implementing websocket support (https://www.varnish-cache.org/docs/4.0/users-guide/vcl-example-websockets.html)
	if (req.http.upgrade) {
		set bereq.http.upgrade = req.http.upgrade;
	}

	return (pipe);
}

sub vcl_purge {
	call ban_purge_vcl_purge;
}