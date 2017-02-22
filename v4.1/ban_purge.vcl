# Only allow purging from specific IPs
acl acl_purge {
    "localhost";
    "127.0.0.1";
    "::1";
}

sub ban_purge_vcl_recv {
    # Allow purging from ACL from method PURGE
    if (req.method == "PURGE") {
        # If not allowed then a error 403 is returned
        if (!client.ip ~ acl_purge) {
            return (synth(405, "This IP is not allowed to send PURGE requests."));
        }
        if (req.http.X-Purge-Method == "regex") {
            ban("req.url ~ " + req.url + " && req.http.host ~ " + req.http.host);
            return (synth(202, "Confirmation de ban de la page"));
        } else {
         	# If allowed, do a cache_lookup -> vlc_hit() or vlc_miss()
        	return (purge);
    	}
    }

    # Allow banning from ACL from method BAN
    if (req.method == "BAN") {
        if (!client.ip ~ acl_purge) {
            return (synth(403, "This IP is not allowed to send BAN requests."));
        }
        # If allowed, do a cache_lookup -> vlc_hit() or vlc_miss()
        ban("req.http.host == " + req.http.host + " && req.url ~ "+req.url); # Send the "purge" command to the purge queue in a REGEXP form
        return (synth(202, "Confirmation de ban de la page"));
    }

    # Allow banning from ACL from browser with Shift + F5
    if (req.http.Pragma ~ "no-cache"
        && req.http.Cache-Control ~ "no-cache"
        && req.method == "GET"
        && client.ip ~ acl_purge ) {

            # Ban specific URL : so host and url must be =
            #ban("req.http.host == " + req.http.host + " && req.url == " + req.url);
            #return (synth(202, "Confirmation de ban de la page http://"+req.http.host+req.url));

            # jump to vcl_hash
            return (purge);
    }
}

#
#
#
sub ban_purge_vcl_purge {
	if (req.http.Pragma ~ "no-cache"
			&& req.http.Cache-Control ~ "no-cache") {
	return (synth(202, "Purge done of page http://"+req.http.host+req.url));
	} else {
		set req.method = "GET";
		return (restart);
	}
}