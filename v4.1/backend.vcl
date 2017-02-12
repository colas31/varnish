probe healthcheck {
        .request =
                "HEAD /check.php HTTP/1.1"
                "Host: tutoandco.colas-delmas.fr"
                "Connection: close";
        .timeout = 5s;
        .interval = 4s;
        .window = 5;
        .threshold = 3;
}

backend backend1 {
        .host = "127.0.0.1";
        .port = "8080";
        .max_connections = 300;
        .connect_timeout = 180s;
        .first_byte_timeout = 600s;
        .between_bytes_timeout = 180s;
        .probe = healthcheck;
}
