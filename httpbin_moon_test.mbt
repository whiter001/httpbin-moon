fn make_context(
  http_method : String,
  path : String,
  query : String,
  headers : Map[String, String],
  body : Bytes,
  origin : String,
) -> RequestContext {
  make_request_context(
    http_method,
    path,
    query,
    "localhost:8080",
    "http",
    headers,
    body,
    origin,
  )
}

fn body_text(spec : ResponseSpec) -> String {
  @utf8.decode_lossy(spec.body)
}

fn parse_echo(spec : ResponseSpec) -> EchoPayload {
  try {
    @json.from_json(@json.parse(body_text(spec).trim()))
  } catch {
    _ => abort("failed to parse echo payload")
  }
}

test "get echoes request metadata" {
  let ctx = make_context(
    "GET",
    "/get",
    "animal=dog&animal=cat&empty=",
    {
      "Host": "localhost:8080",
      "User-Agent": "moon-test",
    },
    b"",
    "127.0.0.1",
  )
  let spec = route_request(ctx)
  assert_eq(spec.status, 200)
  let payload = parse_echo(spec)
  assert_eq(payload.http_method, "GET")
  assert_eq(payload.path, "/get")
  assert_eq(payload.url, "http://localhost:8080/get?animal=dog&animal=cat&empty=")
  assert_eq(payload.origin, "127.0.0.1")
  guard payload.args.get("animal") is Some(values) else {
    fail("missing animal query values")
  }
  assert_eq(values, ["dog", "cat"])
}

test "post parses json body" {
  let body = "{\"title\":\"MoonBit\"}"
  let ctx = make_context(
    "POST",
    "/post",
    "",
    {
      "Host": "localhost:8080",
      "Content-Type": "application/json",
    },
    @utf8.encode(body),
    "127.0.0.1",
  )
  let spec = route_request(ctx)
  let payload = parse_echo(spec)
  assert_eq(payload.data, body)
  assert_eq(payload.json, Some(body))
}

test "response-headers route keeps duplicate query values" {
  let ctx = make_context(
    "GET",
    "/response-headers",
    "animal=dog&animal=cat&x-answer=42",
    { "Host": "localhost:8080" },
    b"",
    "127.0.0.1",
  )
  let spec = route_request(ctx)
  assert_eq(spec.status, 200)
  assert_eq(spec.headers.get_or_default("animal", ""), "dog, cat")
}

test "status and redirect routes work" {
  let status_spec = route_request(
    make_context("GET", "/status/418", "", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  assert_eq(status_spec.status, 418)
  assert_eq(status_spec.reason, "I'm a teapot")

  let redirect_spec = route_request(
    make_context("GET", "/absolute-redirect/2", "", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  assert_eq(redirect_spec.status, 302)
  assert_eq(redirect_spec.headers.get_or_default("Location", ""), "http://localhost:8080/absolute-redirect/1")

  let relative_spec = route_request(
    make_context("GET", "/relative-redirect/2", "", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  assert_eq(relative_spec.headers.get_or_default("Location", ""), "/relative-redirect/1")
}

test "uuid route returns uuid-shaped value" {
  let spec = route_request(
    make_context("GET", "/uuid", "", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  let payload : UuidPayload = @json.from_json(@json.parse(body_text(spec).trim()))
  assert_eq(payload.uuid.length(), 36)
  assert_eq(payload.uuid.sub(start=14, end=15).to_string(), "4")
}

test "anything route preserves tail path" {
  let spec = route_request(
    make_context("PATCH", "/anything/foo/bar", "x=1", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  let payload = parse_echo(spec)
  assert_eq(payload.path, "/anything/foo/bar")
}

test "cookie set returns cookie headers" {
  let spec = route_request(
    make_context("GET", "/cookies/set", "a=1&b=2", { "Host": "localhost:8080" }, b"", "127.0.0.1"),
  )
  assert_eq(spec.status, 302)
  assert_eq(spec.cookies.length(), 2)
}

test "basic auth validates credentials" {
  let bad = route_request(
    make_context("GET", "/basic-auth/u/p", "", {}, b"", "127.0.0.1"),
  )
  assert_eq(bad.status, 401)

  let good = route_request(
    make_context(
      "GET",
      "/basic-auth/u/p",
      "",
      { "Authorization": "Basic dTpw" },
      b"",
      "127.0.0.1",
    ),
  )
  assert_eq(good.status, 200)
}

test "bytes and image routes return binary payload" {
  let bytes_spec = route_request(
    make_context("GET", "/bytes/16", "", {}, b"", "127.0.0.1"),
  )
  assert_eq(bytes_spec.status, 200)
  assert_eq(bytes_spec.body.length(), 16)

  let image_spec = route_request(
    make_context("GET", "/image/png", "", {}, b"", "127.0.0.1"),
  )
  assert_eq(image_spec.status, 200)
  assert_true(image_spec.body.length() > 10)
}