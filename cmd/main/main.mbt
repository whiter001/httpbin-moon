async fn main {
  let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:8080"), reuse_addr=true) catch {
    err => {
      println("failed to start server: \{err}")
      return
    }
  }

  println("httpbin-moon listening on http://127.0.0.1:8080")
  @async.sleep(0)

  server.run_forever((request, body, conn) => {
    let raw_body = try body.read_all().binary() catch {
      _ => b""
    }
    let (path, query) = @app.split_target(request.path)
    let headers = request.headers.copy()
    let host = match @app.header_value_ci(headers, "Host") {
      Some(value) => value
      None => "127.0.0.1:8080"
    }
    let scheme = match @app.header_value_ci(headers, "X-Forwarded-Proto") {
      Some(value) => value
      None => "http"
    }
    let origin = match @app.header_value_ci(headers, "X-Forwarded-For") {
      Some(value) => value
      None => "\{conn.client_addr()}"
    }
    let ctx = @app.make_request_context(
      match request.meth {
        Get => "GET"
        Head => "HEAD"
        Post => "POST"
        Put => "PUT"
        Delete => "DELETE"
        Connect => "CONNECT"
        Options => "OPTIONS"
        Trace => "TRACE"
        Patch => "PATCH"
      },
      path,
      query,
      host,
      scheme,
      headers,
      raw_body,
      origin,
    )

    let spec = @app.route_request(ctx)
    let response_headers = spec.headers.copy()
    response_headers.set("Content-Type", spec.content_type)
    conn
    ..send_response(
      spec.status,
      spec.reason,
      extra_headers=response_headers,
      cookies=spec.cookies,
    )
    ..write(spec.body)
    .end_response()
  })
}