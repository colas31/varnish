sub static_files_vcl_recv {
   # Remove all cookies for static files
    # A valid discussion could be held on this line: do you really need to cache static files that don't cause load?
    # Only if you have memory left.
    # Sure, there's disk I/O, but chances are your OS will already have these files in their buffers (thus memory).
    # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files-in-varnish/
    if (req.url ~ "^[^?]*\.(css|bmp|bz2|js|doc|eot|flv|gif|gz|ico|jpeg|jpg|less|pdf|png|rtf|swf|txt|woff|xml)(\?.*)?$") {
	    set req.http.X-Pass = "Static files";
	    unset req.http.Cookie;
    }

	 # No cache for big video files
	 if (req.url ~ "\.(avi|mp4)") {
		set req.http.X-Pass = "Videos";
		return (pass);
	 }

}

sub static_files_vcl_backend_response {

    # Bypass cache for files > 10 MB
    if (std.integer(beresp.http.Content-Length, 0) > 10485760) {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }
}