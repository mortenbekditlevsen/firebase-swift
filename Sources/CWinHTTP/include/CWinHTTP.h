// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A WebSocket client over WinHTTP, for WinHTTPDatabaseTransport.
//
// The API uses portable types only, so Swift sees none of WinHTTP's macros,
// enums or handle types. The calls block. Any of them may run while another
// thread calls CWinHTTPSocketAbort, which ends them.

#ifndef CWINHTTP_H
#define CWINHTTP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A WebSocket connection, from opening to closing.
typedef struct CWinHTTPSocket CWinHTTPSocket;

/// What a CWinHTTPSocketReceive call got.
enum {
  /// The end of a message, or all of it.
  CWinHTTPReceivedMessage = 0,
  /// Part of a message; more follows.
  CWinHTTPReceivedFragment = 1,
  /// The server's close frame.
  CWinHTTPReceivedClose = 2,
};

/// The error the calls return after CWinHTTPSocketAbort
/// (ERROR_WINHTTP_OPERATION_CANCELLED).
extern const uint32_t CWinHTTPErrorCancelled;

/// Returns NULL if out of memory.
CWinHTTPSocket *CWinHTTPSocketCreate(void);

/// Aborts the socket, and frees it once WinHTTP is done with it. No other
/// call may be running, or start.
void CWinHTTPSocketDestroy(CWinHTTPSocket *socket);

/// Connects and upgrades to a WebSocket.
///
/// The strings are NUL-terminated UTF-16. `headers` is "Name: value\r\n" for
/// each header (it may be empty). `timeoutMilliseconds` bounds resolving,
/// connecting, and each send and receive of the upgrade.
///
/// Returns 0 or a Windows error code. On 0, `statusCode` is the response's
/// status: the socket is open only if it's 101.
uint32_t CWinHTTPSocketOpen(CWinHTTPSocket *socket, const uint16_t *userAgent,
                            const uint16_t *host, uint16_t port, int secure,
                            const uint16_t *pathAndQuery, const uint16_t *headers,
                            uint32_t timeoutMilliseconds, uint32_t *statusCode);

/// Receives up to `length` bytes of the next message into `buffer`.
///
/// Returns 0 or a Windows error code. On 0, `bytesRead` and `received` (one of
/// the CWinHTTPReceived values) say what arrived.
uint32_t CWinHTTPSocketReceive(CWinHTTPSocket *socket, void *buffer, uint32_t length,
                               uint32_t *bytesRead, int32_t *received);

/// Sends a text message. Returns 0 or a Windows error code.
uint32_t CWinHTTPSocketSend(CWinHTTPSocket *socket, const void *bytes, uint32_t length);

/// Sends a close frame (1000, normal closure) without waiting for the
/// server's. Returns 0 or a Windows error code.
uint32_t CWinHTTPSocketShutdown(CWinHTTPSocket *socket);

/// Closes the connection's handles, which ends any call in progress (with
/// CWinHTTPErrorCancelled) and every later one. Any thread may call it, more
/// than once.
void CWinHTTPSocketAbort(CWinHTTPSocket *socket);

#ifdef __cplusplus
}
#endif

#endif  // CWINHTTP_H
