pub struct RequestContext {
  http_method : String
  path : String
  query : String
  host : String
  scheme : String
  headers : Map[String, String]
  body : Bytes
  origin : String
}

pub fn make_request_context(
  http_method : String,
  path : String,
  query : String,
  host : String,
  scheme : String,
  headers : Map[String, String],
  body : Bytes,
  origin : String,
) -> RequestContext {
  RequestContext::{
    http_method,
    path,
    query,
    host,
    scheme,
    headers,
    body,
    origin,
  }
}

pub struct ResponseSpec {
  status : Int
  reason : String
  content_type : String
  headers : Map[String, String]
  body : Bytes
  cookies : Array[@http.Cookie]
}

pub struct EchoPayload {
  args : Map[String, Array[String]]
  data : String
  files : Map[String, String]
  form : Map[String, String]
  headers : Map[String, String]
  json : String?
  origin : String
  url : String
  http_method : String
  path : String
} derive(ToJson, FromJson)

pub struct UuidPayload {
  uuid : String
} derive(ToJson, FromJson)

pub struct ResponseHeadersPayload {
  headers : Map[String, Array[String]]
} derive(ToJson, FromJson)

pub struct AuthPayload {
  authenticated : Bool
  user : String?
  token : String?
} derive(ToJson)

let image_png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"

pub fn split_target(target : String) -> (String, String) {
  if target.split("?").collect() is [path, query] {
    let p = if path.is_empty() { "/" } else { path.to_string() }
    (p, query.to_string())
  } else {
    (if target.is_empty() { "/" } else { target }, "")
  }
}

pub fn header_value_ci(headers : Map[String, String], key : String) -> String? {
  let target = key.to_lower()
  for pair in headers.to_array() {
    let (name, value) = pair
    if name.to_lower() == target {
      return Some(value)
    }
  }
  None
}

fn make_spec(
  status : Int,
  reason : String,
  content_type : String,
  body : Bytes,
  headers : Map[String, String],
  cookies : Array[@http.Cookie],
) -> ResponseSpec {
  ResponseSpec::{ status, reason, content_type, headers, body, cookies }
}

fn json_response_from[X : ToJson](value : X) -> ResponseSpec {
  make_spec(
    200,
    "OK",
    "application/json; charset=utf-8",
    @utf8.encode(value.to_json().stringify()),
    {},
    [],
  )
}

fn text_response(text : String, status : Int, reason : String) -> ResponseSpec {
  make_spec(status, reason, "text/plain; charset=utf-8", @utf8.encode(text), {}, [])
}

fn parse_query(query : String) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = {}
  if query.is_empty() {
    return out
  }
  for raw_pair in query.split("&").collect() {
    if raw_pair.is_empty() {
      continue
    }
    let pair = raw_pair.to_string()
    let key = if pair.find("=") is Some(idx) {
      pair.sub(start=0, end=idx).to_string()
    } else {
      pair
    }
    let value = if pair.find("=") is Some(idx) {
      pair.sub(start=idx + 1, end=pair.length()).to_string()
    } else {
      ""
    }
    if out.get(key) is Some(values) {
      values.push(value)
      out.set(key, values)
    } else {
      out.set(key, [value])
    }
  }
  out
}

fn parse_cookie_header(header : String) -> Map[String, String] {
  let cookies : Map[String, String] = {}
  for part in header.split(";").collect() {
    let item = part.trim().to_string()
    if item.find("=") is Some(idx) {
      let key = item.sub(start=0, end=idx).trim().to_string()
      let value = item.sub(start=idx + 1, end=item.length()).trim().to_string()
      cookies.set(key, value)
    }
  }
  cookies
}

fn build_url(ctx : RequestContext) -> String {
  if ctx.query.is_empty() {
    "\{ctx.scheme}://\{ctx.host}\{ctx.path}"
  } else {
    "\{ctx.scheme}://\{ctx.host}\{ctx.path}?\{ctx.query}"
  }
}

fn make_echo(ctx : RequestContext) -> EchoPayload {
  let body_text = @utf8.decode_lossy(ctx.body)
  let ct = header_value_ci(ctx.headers, "Content-Type").unwrap_or("")
  EchoPayload::{
    args: parse_query(ctx.query),
    data: body_text,
    files: {},
    form: if ct.contains("application/x-www-form-urlencoded") {
      let out : Map[String, String] = {}
      for p in body_text.split("&").collect() {
        if p.find("=") is Some(i) {
          out.set(
            p.sub(start=0, end=i).to_string(),
            p.sub(start=i + 1, end=p.length()).to_string(),
          )
        }
      }
      out
    } else {
      {}
    },
    headers: ctx.headers,
    json: if ct.contains("application/json") && @json.valid(body_text) {
      Some(body_text)
    } else {
      None
    },
    origin: ctx.origin,
    url: build_url(ctx),
    http_method: ctx.http_method,
    path: ctx.path,
  }
}

fn maybe_int(text : String) -> Int? {
  try {
    Some(@string.parse_int(text))
  } catch {
    _ => None
  }
}

fn uuid_v4() -> String {
  let rand = @random.Rand::new()
  let hex = "0123456789abcdef"
  let mut out = ""
  for i in 0..<16 {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      out = out + "-"
    }
    let mut b = rand.int(limit=256)
    if i == 6 {
      b = (b & 0x0F) | 0x40
    }
    if i == 8 {
      b = (b & 0x3F) | 0x80
    }
    out = out +
      hex.sub(start=b / 16, end=b / 16 + 1).to_string() +
      hex.sub(start=b % 16, end=b % 16 + 1).to_string()
  }
  out
}

fn status_reason(code : Int) -> String {
  match code {
    200 => "OK"
    302 => "FOUND"
    400 => "BAD REQUEST"
    401 => "UNAUTHORIZED"
    404 => "NOT FOUND"
    418 => "I'm a teapot"
    _ => "UNKNOWN"
  }
}

fn basic_auth_ok(auth_header : String, user : String, passwd : String) -> Bool {
  guard auth_header.strip_prefix("Basic ") is Some(token) else { return false }
  let decoded = try {
    @base64.decode(token.trim())
  } catch {
    _ => return false
  }
  @utf8.decode_lossy(decoded) == "\{user}:\{passwd}"
}

pub fn route_request(ctx : RequestContext) -> ResponseSpec {
  if ctx.path == "/get" || ctx.path == "/post" || ctx.path == "/put" ||
    ctx.path == "/patch" || ctx.path == "/delete" || ctx.path == "/anything" ||
    ctx.path.strip_prefix("/anything/") is Some(_) {
    return json_response_from(make_echo(ctx))
  }

  if ctx.path == "/uuid" {
    return json_response_from(UuidPayload::{ uuid: uuid_v4() })
  }

  if ctx.path == "/response-headers" {
    let query = parse_query(ctx.query)
    let headers = {}
    for pair in query.to_array() {
      let (name, values) = pair
      headers.set(name, values.join(", "))
    }
    return make_spec(
      200,
      "OK",
      "application/json; charset=utf-8",
      @utf8.encode(ResponseHeadersPayload::{ headers: query }.to_json().stringify()),
      headers,
      [],
    )
  }

  if ctx.path == "/cookies/set" {
    let cookies : Array[@http.Cookie] = []
    for pair in parse_query(ctx.query).to_array() {
      let (name, values) = pair
      if values.length() > 0 {
        cookies.push(@http.Cookie::new(name, values[0], path="/"))
      }
    }
    return make_spec(302, "FOUND", "text/plain; charset=utf-8", b"", { "Location": "/cookies" }, cookies)
  }

  if ctx.path == "/cookies" {
    let cookies = if header_value_ci(ctx.headers, "Cookie") is Some(raw) {
      parse_cookie_header(raw)
    } else {
      {}
    }
    return make_spec(
      200,
      "OK",
      "application/json; charset=utf-8",
      @utf8.encode({ "cookies": cookies }.to_json().stringify()),
      {},
      [],
    )
  }

  if ctx.path == "/image/png" {
    return make_spec(200, "OK", "image/png", @base64.decode_lossy(image_png_b64), {}, [])
  }

  if ctx.path == "/bearer" {
    let auth = header_value_ci(ctx.headers, "Authorization").unwrap_or("")
    if auth.strip_prefix("Bearer ") is Some(token) && !token.trim().is_empty() {
      return json_response_from(
        AuthPayload::{
          authenticated: true,
          user: None,
          token: Some(token.trim().to_string()),
        },
      )
    }
    return make_spec(
      401,
      "UNAUTHORIZED",
      "application/json; charset=utf-8",
      @utf8.encode(AuthPayload::{ authenticated: false, user: None, token: None }.to_json().stringify()),
      { "WWW-Authenticate": "Bearer" },
      [],
    )
  }

  let parts : Array[String] = {
    if ctx.path.strip_prefix("/") is Some(rest) {
      let out : Array[String] = []
      for seg in rest.to_string().split("/").collect() {
        out.push(seg.to_string())
      }
      out
    } else {
      []
    }
  }

  if parts.length() == 2 && parts[0] == "status" {
    if maybe_int(parts[1]) is Some(code) {
      return make_spec(code, status_reason(code), "text/plain; charset=utf-8", b"", {}, [])
    }
  }

  if parts.length() == 2 && parts[0] == "absolute-redirect" {
    if maybe_int(parts[1]) is Some(count) {
      let next = count - 1
      let location = if next <= 0 {
        "\{ctx.scheme}://\{ctx.host}/get"
      } else {
        "\{ctx.scheme}://\{ctx.host}/absolute-redirect/\{next}"
      }
      return make_spec(302, "FOUND", "text/plain; charset=utf-8", b"", { "Location": location }, [])
    }
  }

  if parts.length() == 2 && parts[0] == "relative-redirect" {
    if maybe_int(parts[1]) is Some(count) {
      let next = count - 1
      let location = if next <= 0 { "/get" } else { "/relative-redirect/\{next}" }
      return make_spec(302, "FOUND", "text/plain; charset=utf-8", b"", { "Location": location }, [])
    }
  }

  if parts.length() == 3 && parts[0] == "basic-auth" {
    let user = parts[1]
    let pass = parts[2]
    let auth = header_value_ci(ctx.headers, "Authorization").unwrap_or("")
    if basic_auth_ok(auth, user, pass) {
      return json_response_from(AuthPayload::{ authenticated: true, user: Some(user), token: None })
    }
    return make_spec(
      401,
      "UNAUTHORIZED",
      "text/plain; charset=utf-8",
      b"",
      { "WWW-Authenticate": "Basic realm=\"Fake Realm\"" },
      [],
    )
  }

  if parts.length() == 2 && parts[0] == "bytes" {
    if maybe_int(parts[1]) is Some(n) {
      let size = if n < 0 { 0 } else { n }
      let rand = @random.Rand::new()
      return make_spec(
        200,
        "OK",
        "application/octet-stream",
        Bytes::makei(size, _ => rand.int(limit=256).to_byte()),
        {},
        [],
      )
    }
  }

  text_response("Not Found", 404, "NOT FOUND")
}
