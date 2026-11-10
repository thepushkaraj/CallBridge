# The CallBridge Protocol

CallBridge clients and servers speak plain HTTP/1.1 with JSON bodies.
This document is the entire spec — if you can implement what's here, you
can interoperate with any CallBridge app.

## Endpoint

```
POST /call
```

The server listens on TCP port `8765` by default (configurable).

## Request headers

| Header               | Required | Description                                              |
|----------------------|----------|----------------------------------------------------------|
| `Content-Type`       | yes      | `application/json`                                       |
| `X-CallBridge-Secret`| optional | Shared secret. If the server has one configured, requests without a matching value are rejected with `401`. |

## Request body

```json
{
  "event":  "ringing",
  "number": "+15550101234",
  "caller": "Mom",
  "device": "Pixel 7"
}
```

| Field    | Type   | Required | Description                                                        |
|----------|--------|----------|--------------------------------------------------------------------|
| `event`  | string | yes      | See [Events](#events). Unknown values must be ignored gracefully (respond `200`, optionally log). |
| `number` | string | no       | Caller or sender phone number in E.164 when available, otherwise empty string. |
| `caller` | string | no       | Contact name when resolvable, otherwise empty string.              |
| `body`   | string | no       | Message text (`sms` events only). Concatenated SMS parts are joined; may contain newlines. |
| `device` | string | no       | Human-readable name of the sending device, e.g. the phone model.   |

All fields except `event` may be omitted or empty; servers must handle
their absence.

## Events

| Value     | Meaning                                        | Status        |
|-----------|------------------------------------------------|---------------|
| `ringing` | Phone is ringing for an incoming call          | stable        |
| `sms`     | An SMS text message was received on the phone  | v0.3.0        |
| `test`    | Connectivity test sent from the settings screen| stable        |
| `missed`  | Incoming call was not answered                 | planned       |

## Responses

Servers respond `200 OK` on success (body is unspecified; the reference
server sends `{"ok":true}`). Error codes:

| Code | Meaning                                                       |
|------|---------------------------------------------------------------|
| 400  | Body is not valid JSON or `event` is missing                  |
| 401  | Server requires a secret and it was missing or wrong           |
| 404  | Path is not `/call`                                            |

## Pairing QR payload

The macOS app renders its connection settings as a QR code so the Android
app can pair without typing. The QR contains this JSON:

```json
{
  "app": "callbridge",
  "v": 1,
  "host": "192.168.1.20",
  "port": 8765,
  "secret": "hunter2"
}
```

| Field    | Type   | Required | Description                                              |
|----------|--------|----------|----------------------------------------------------------|
| `app`    | string | no       | Fixed `callbridge`. Readers should reject other values.  |
| `v`      | number | no       | Payload version, currently `1`.                          |
| `host`   | string | yes      | IPv4 address of the Mac on the shared network.           |
| `port`   | number | yes      | TCP port the listener accepts calls on.                  |
| `secret` | string | no       | Omitted when no shared secret is configured.             |

Readers must ignore unknown fields.

## Reference exchange

```bash
$ curl -i http://192.168.1.20:8765/call \
    -H 'Content-Type: application/json' \
    -H 'X-CallBridge-Secret: hunter2' \
    -d '{"event":"test","device":"Pixel 7"}'

HTTP/1.1 200 OK
Content-Type: application/json

{"ok":true}
```

## Design constraints

These are deliberate; please keep them true:

1. **One request, one notification.** No sessions, websockets, retries,
   or acks beyond the HTTP status code.
2. **No cloud.** Everything works on an isolated LAN with no internet.
3. **Human-debuggable.** Any event can be sent with `curl`.
