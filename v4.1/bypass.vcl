sub bypass_varnish_cookies {
	# Check the cookies for bypass Varnish cache
	if (req.http.Cookie ~ "bypass_varnish") {
		set req.http.X-Pass = "Cookies";
		return (pass);
	}
}

sub bypass_varnish_urls {
	# Don't cache some URLs (security in case missing header in PHP)
	if (req.url ~ "/(.*)sitemap(.*).xml") {
		set req.http.X-Pass = "Urls";
		return(pass);
	}
}