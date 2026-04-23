# httpbin-moon

MoonBit 版的轻量 httpbin 风格服务，当前实现覆盖这些路由：

- `GET /get`
- `POST /post`
- `GET /headers`
- `GET /ip`
- `GET /uuid`
- `GET /status/<code>`
- `GET /response-headers?...`
- `GET /anything` 和 `GET /anything/<path>`
- `GET /redirect/<n>`、`/relative-redirect/<n>`、`/absolute-redirect/<n>`

运行服务：

```sh
moon run cmd/main
```

运行测试：

```sh
moon test
```