sub wordpress_vcl_recv {
	# --- Wordpress specific configuration

    # don't need too different cache for Wordpress, theme are fully responsive
    set req.http.X-User-Agent = "desktop";

	# WordPress sets many cookies that are safe to ignore. To remove them, add the following lines
	#https://info.varnish-software.com/blog/varnish-wiki-highlights-wordpress
	set req.http.cookie = regsuball(req.http.cookie, "wp-settings-\d+=[^;]+(; )?", "");
    set req.http.cookie = regsuball(req.http.cookie, "wp-settings-time-\d+=[^;]+(; )?", "");
    set req.http.cookie = regsuball(req.http.cookie, "wordpress_test_cookie=[^;]+(; )?", "
	if (req.http.cookie == "") {
		unset req.http.cookie;
	}

	# Check the cookies for wordpress-specific items
	if (req.http.Cookie ~ "wordpress_"
	    || req.http.Cookie ~ "comment_") {
	    set req.http.X-Pass = "Wordpress Cookies";
		return (pass);
	}

    # Don't cache some URL :
    # - Search result
    # - feed
	# - Blitz hack
	# - Admin page
	# - WooCommerce pages
	if (req.url ~ "\?s="
	    || req.url ~ "/feed"
	    || req.url ~ "/mu-.*"
	    || req.url ~ "/wp-(login|admin)"
	    || req.url ~ "/(cart|my-account|checkout|addons|/?add-to-cart=)") {

        set req.http.X-Pass = "Wordpress Urls";
        return (pass);
	}


	# --- End of Wordpress specific configuration
}

sub wordpress_vcl_backend_response {
	# allow cookies to be set only if you are on admin pages or WooCommerce-specific pages
	if (bereq.url !~ "wp-admin|wp-login|product|cart|checkout|my-account|/?remove_item=") {
		unset beresp.http.set-cookie;
	}

    # extending caching time
	set beresp.ttl = 1w;
}
