sub cookies_vcl_recv {
	# removes all cookies named __utm? (utma, utmb...) - tracking thing
	set req.http.Cookie = regsuball(req.http.Cookie, "(^|(?<=; )) *__utm.=[^;]+;? *", "\1");

    # Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

    # Remove DoubleClick offensive cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

    # Remove the Quant Capital cookies (added by some plugin, all __qca)
    set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

    # Remove the AddThis cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

    # Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

    # Are there cookies left with only spaces or that are empty?
	if (req.http.Cookie == "" || req.http.cookie ~ "^\s*$") {
		unset req.http.Cookie;
	}
}