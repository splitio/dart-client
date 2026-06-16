# http_client

Buffered HTTP request/response abstraction (Axis-1 SPI). Encapsulates runtime HTTP mechanics and is easily swappable for testing.

## Key exports

| Type | Description |
|---|---|
| `HttpClient` | Interface for making buffered HTTP requests |
| `HttpResponse` | Response envelope (status code, headers, body) |
| `HttpStatus` | HTTP status code taxonomy and categorization |

## Dependencies

**Internal:** none  
**External:** package:http

## Spec reference

SDK Specification v1 §3.1 — Shared core (platform SPIs); §6 — Port & SPI Contracts
