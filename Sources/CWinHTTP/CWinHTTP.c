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

#include "CWinHTTP.h"

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winhttp.h>

#include <stdlib.h>
#include <string.h>
#include <wchar.h>

// WinHTTP runs asynchronously here (WINHTTP_FLAG_ASYNC), because that's the
// mode in which closing a handle ends what's pending on it: a synchronous call
// must not have its handle closed from another thread. Each call starts an
// operation and waits for it to complete, which happens in the status
// callback: with the operation's own notification, with REQUEST_ERROR, or with
// its handle's HANDLE_CLOSING, the handle's last callback. Until then WinHTTP
// may still use the operation's buffer, so the buffers are the socket's own,
// and the socket is freed only after every handle has closed.

const uint32_t CWinHTTPErrorCancelled = ERROR_WINHTTP_OPERATION_CANCELLED;

// How long an open connection waits for a message before WinHTTP reports a
// timeout, which CWinHTTPSocketReceive then waits through. (Finite rather than
// infinite, so a receive can't be cut short by a misread setting.)
static const DWORD kIdleReceiveTimeout = 24 * 60 * 60 * 1000;

enum { kReceiveBufferSize = 64 * 1024 };

typedef struct {
  BOOL pending;
  HINTERNET handle;
  DWORD error;
  DWORD bytes;
  WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
} Operation;

struct CWinHTTPSocket {
  SRWLOCK lock;
  CONDITION_VARIABLE changed;
  BOOL aborted;
  // CWinHTTPSocketDestroy was called: free the socket when `live` is 0.
  BOOL destroyed;
  // Handles whose HANDLE_CLOSING hasn't come yet.
  LONG live;
  HINTERNET session;
  HINTERNET connection;
  HINTERNET request;
  HINTERNET webSocket;
  // The upgrade (sending the request, then receiving the response).
  Operation open;
  Operation receive;
  Operation send;
  Operation shutdown;
  BYTE *receiveBuffer;
  BYTE *sendBuffer;
};

CWinHTTPSocket *CWinHTTPSocketCreate(void) {
  CWinHTTPSocket *socket = calloc(1, sizeof *socket);
  if (!socket) {
    return NULL;
  }
  socket->receiveBuffer = malloc(kReceiveBufferSize);
  if (!socket->receiveBuffer) {
    free(socket);
    return NULL;
  }
  InitializeSRWLock(&socket->lock);
  InitializeConditionVariable(&socket->changed);
  return socket;
}

static void Free(CWinHTTPSocket *socket) {
  free(socket->receiveBuffer);
  free(socket->sendBuffer);
  free(socket);
}

void CWinHTTPSocketDestroy(CWinHTTPSocket *socket) {
  if (!socket) {
    return;
  }
  CWinHTTPSocketAbort(socket);
  // WinHTTP calls back until each handle's HANDLE_CLOSING; the last one frees
  // the socket if it hasn't come yet.
  AcquireSRWLockExclusive(&socket->lock);
  socket->destroyed = TRUE;
  BOOL done = socket->live == 0;
  ReleaseSRWLockExclusive(&socket->lock);
  if (done) {
    Free(socket);
  }
}

// MARK: - Operations

// Completes `operation` (under the lock).
static void CompleteLocked(CWinHTTPSocket *socket, Operation *operation, DWORD error, DWORD bytes,
                           WINHTTP_WEB_SOCKET_BUFFER_TYPE type) {
  if (operation->pending) {
    operation->pending = FALSE;
    operation->error = error;
    operation->bytes = bytes;
    operation->type = type;
    WakeAllConditionVariable(&socket->changed);
  }
}

static void Complete(CWinHTTPSocket *socket, Operation *operation, DWORD error, DWORD bytes,
                     WINHTTP_WEB_SOCKET_BUFFER_TYPE type) {
  AcquireSRWLockExclusive(&socket->lock);
  CompleteLocked(socket, operation, error, bytes, type);
  ReleaseSRWLockExclusive(&socket->lock);
}

// Marks `operation` as started on `handle`, unless the socket has been
// aborted (or the handle closed), or it's already under way. Call before the
// WinHTTP call that starts it: its callback may come before that call returns.
static BOOL Begin(CWinHTTPSocket *socket, Operation *operation, HINTERNET *slot) {
  AcquireSRWLockExclusive(&socket->lock);
  BOOL started = !socket->aborted && *slot != NULL && !operation->pending;
  if (started) {
    operation->pending = TRUE;
    operation->handle = *slot;
    operation->error = NO_ERROR;
    operation->bytes = 0;
  }
  ReleaseSRWLockExclusive(&socket->lock);
  return started;
}

// Waits for `operation` to complete, and returns its error: "cancelled" if
// the socket was aborted meanwhile, since closing a handle fails what's
// pending on it with various errors.
static uint32_t Wait(CWinHTTPSocket *socket, Operation *operation) {
  AcquireSRWLockExclusive(&socket->lock);
  while (operation->pending) {
    SleepConditionVariableSRW(&socket->changed, &socket->lock, INFINITE, 0);
  }
  DWORD error = operation->error;
  if (error != NO_ERROR && socket->aborted) {
    error = ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  ReleaseSRWLockExclusive(&socket->lock);
  return error;
}

// Ends `operation` when the call meant to start it failed, which means it
// didn't start (no callback will come), and returns the outcome.
static uint32_t NotStarted(CWinHTTPSocket *socket, Operation *operation, DWORD error) {
  AcquireSRWLockExclusive(&socket->lock);
  operation->pending = FALSE;
  WakeAllConditionVariable(&socket->changed);
  if (socket->aborted) {
    error = ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  ReleaseSRWLockExclusive(&socket->lock);
  return error;
}

// The outcome of a synchronous WinHTTP call that failed with `error`.
static uint32_t Outcome(CWinHTTPSocket *socket, DWORD error) {
  AcquireSRWLockShared(&socket->lock);
  BOOL aborted = socket->aborted;
  ReleaseSRWLockShared(&socket->lock);
  return aborted ? ERROR_WINHTTP_OPERATION_CANCELLED : error;
}

// MARK: - Callback

static void Closed(CWinHTTPSocket *socket, HINTERNET handle) {
  AcquireSRWLockExclusive(&socket->lock);
  Operation *operations[] = {&socket->open, &socket->receive, &socket->send, &socket->shutdown};
  for (size_t index = 0; index < sizeof operations / sizeof operations[0]; index++) {
    if (operations[index]->handle == handle) {
      CompleteLocked(socket, operations[index], ERROR_WINHTTP_OPERATION_CANCELLED, 0,
                     WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
    }
  }
  socket->live -= 1;
  BOOL free = socket->destroyed && socket->live == 0;
  ReleaseSRWLockExclusive(&socket->lock);
  if (free) {
    Free(socket);
  }
}

static void Failed(CWinHTTPSocket *socket, HINTERNET handle, void *info, DWORD infoLength) {
  AcquireSRWLockExclusive(&socket->lock);
  if (handle == socket->open.handle) {
    // From WinHttpSendRequest or WinHttpReceiveResponse.
    if (infoLength >= sizeof(WINHTTP_ASYNC_RESULT)) {
      DWORD error = ((WINHTTP_ASYNC_RESULT *)info)->dwError;
      CompleteLocked(socket, &socket->open, error, 0,
                     WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
    }
  } else if (infoLength >= sizeof(WINHTTP_WEB_SOCKET_ASYNC_RESULT)) {
    // From an operation on the WebSocket.
    WINHTTP_WEB_SOCKET_ASYNC_RESULT *result = info;
    Operation *operation = NULL;
    switch (result->Operation) {
      case WINHTTP_WEB_SOCKET_SEND_OPERATION:
        operation = &socket->send;
        break;
      case WINHTTP_WEB_SOCKET_RECEIVE_OPERATION:
        operation = &socket->receive;
        break;
      case WINHTTP_WEB_SOCKET_SHUTDOWN_OPERATION:
        operation = &socket->shutdown;
        break;
      default:
        break;
    }
    if (operation) {
      CompleteLocked(socket, operation, result->AsyncResult.dwError, 0,
                     WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
    }
  }
  ReleaseSRWLockExclusive(&socket->lock);
}

static void CALLBACK Callback(HINTERNET handle, DWORD_PTR context, DWORD status, LPVOID info,
                              DWORD infoLength) {
  CWinHTTPSocket *socket = (CWinHTTPSocket *)context;
  if (!socket) {
    return;
  }
  switch (status) {
    case WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
    case WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE:
      Complete(socket, &socket->open, NO_ERROR, 0, WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
      break;
    case WINHTTP_CALLBACK_STATUS_READ_COMPLETE:
      if (infoLength >= sizeof(WINHTTP_WEB_SOCKET_STATUS)) {
        WINHTTP_WEB_SOCKET_STATUS *result = info;
        Complete(socket, &socket->receive, NO_ERROR, result->dwBytesTransferred,
                 result->eBufferType);
      }
      break;
    case WINHTTP_CALLBACK_STATUS_WRITE_COMPLETE:
      Complete(socket, &socket->send, NO_ERROR, 0, WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
      break;
    case WINHTTP_CALLBACK_STATUS_SHUTDOWN_COMPLETE:
      Complete(socket, &socket->shutdown, NO_ERROR, 0,
               WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE);
      break;
    case WINHTTP_CALLBACK_STATUS_REQUEST_ERROR:
      Failed(socket, handle, info, infoLength);
      break;
    case WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING:
      Closed(socket, handle);
      break;
    default:
      break;
  }
}

// MARK: - Handles

// Gives a new handle the socket as its context, so its callbacks (above all
// HANDLE_CLOSING) reach the socket, and stores it in `slot`. If the socket has
// been aborted, closes the handle instead and returns FALSE. Returns FALSE,
// with GetLastError's error in `error`, if the context can't be set.
static BOOL Keep(CWinHTTPSocket *socket, HINTERNET *slot, HINTERNET handle, DWORD *error) {
  *error = NO_ERROR;
  DWORD_PTR context = (DWORD_PTR)socket;
  if (!WinHttpSetOption(handle, WINHTTP_OPTION_CONTEXT_VALUE, &context, sizeof context)) {
    *error = GetLastError();
    WinHttpCloseHandle(handle);  // No callbacks reach the socket without a context.
    return FALSE;
  }
  AcquireSRWLockExclusive(&socket->lock);
  socket->live += 1;
  BOOL aborted = socket->aborted;
  if (!aborted) {
    *slot = handle;
  }
  ReleaseSRWLockExclusive(&socket->lock);
  if (aborted) {
    *error = ERROR_WINHTTP_OPERATION_CANCELLED;
    WinHttpCloseHandle(handle);
    return FALSE;
  }
  return TRUE;
}

// The handle in `slot`, or NULL once the socket has been aborted.
static HINTERNET Get(CWinHTTPSocket *socket, HINTERNET *slot) {
  AcquireSRWLockShared(&socket->lock);
  HINTERNET handle = socket->aborted ? NULL : *slot;
  ReleaseSRWLockShared(&socket->lock);
  return handle;
}

// Closes the handle in `slot`.
static void Close(CWinHTTPSocket *socket, HINTERNET *slot) {
  AcquireSRWLockExclusive(&socket->lock);
  HINTERNET handle = *slot;
  *slot = NULL;
  ReleaseSRWLockExclusive(&socket->lock);
  if (handle) {
    WinHttpCloseHandle(handle);
  }
}

void CWinHTTPSocketAbort(CWinHTTPSocket *socket) {
  AcquireSRWLockExclusive(&socket->lock);
  socket->aborted = TRUE;
  HINTERNET handles[] = {socket->webSocket, socket->request, socket->connection,
                         socket->session};
  socket->webSocket = NULL;
  socket->request = NULL;
  socket->connection = NULL;
  socket->session = NULL;
  ReleaseSRWLockExclusive(&socket->lock);
  for (size_t index = 0; index < sizeof handles / sizeof handles[0]; index++) {
    if (handles[index]) {
      WinHttpCloseHandle(handles[index]);
    }
  }
}

// MARK: - Calls

static uint32_t AddHeaders(CWinHTTPSocket *socket, HINTERNET request, const WCHAR *headers) {
  // One at a time: WINHTTP_ADDREQ_FLAG_REPLACE takes a single header.
  const WCHAR *line = headers;
  while (line && *line) {
    const WCHAR *end = wcsstr(line, L"\r\n");
    DWORD length = end ? (DWORD)(end - line) : (DWORD)wcslen(line);
    if (length > 0 &&
        !WinHttpAddRequestHeaders(request, line, length,
                                  WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE)) {
      return Outcome(socket, GetLastError());
    }
    line = end ? end + 2 : line + length;
  }
  return NO_ERROR;
}

uint32_t CWinHTTPSocketOpen(CWinHTTPSocket *socket, const uint16_t *userAgent,
                            const uint16_t *host, uint16_t port, int secure,
                            const uint16_t *pathAndQuery, const uint16_t *headers,
                            uint32_t timeoutMilliseconds, uint32_t *statusCode) {
  *statusCode = 0;
  DWORD error = NO_ERROR;

  HINTERNET session = WinHttpOpen((LPCWSTR)userAgent, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS,
                                  WINHTTP_FLAG_ASYNC);
  if (!session) {
    return Outcome(socket, GetLastError());
  }
  // Set before the other handles, which inherit it.
  if (WinHttpSetStatusCallback(session, Callback, WINHTTP_CALLBACK_FLAG_ALL_NOTIFICATIONS, 0) ==
      WINHTTP_INVALID_STATUS_CALLBACK) {
    error = GetLastError();
    WinHttpCloseHandle(session);
    return Outcome(socket, error);
  }
  if (!Keep(socket, &socket->session, session, &error)) {
    return Outcome(socket, error);
  }
  int timeout = (int)timeoutMilliseconds;
  if (!WinHttpSetTimeouts(session, timeout, timeout, timeout, timeout)) {
    return Outcome(socket, GetLastError());
  }

  HINTERNET connection = WinHttpConnect(session, (LPCWSTR)host, port, 0);
  if (!connection) {
    return Outcome(socket, GetLastError());
  }
  if (!Keep(socket, &socket->connection, connection, &error)) {
    return Outcome(socket, error);
  }

  HINTERNET request = WinHttpOpenRequest(connection, L"GET", (LPCWSTR)pathAndQuery, NULL,
                                         WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                         secure ? WINHTTP_FLAG_SECURE : 0);
  if (!request) {
    return Outcome(socket, GetLastError());
  }
  if (!Keep(socket, &socket->request, request, &error)) {
    return Outcome(socket, error);
  }
  if (!WinHttpSetOption(request, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0)) {
    return Outcome(socket, GetLastError());
  }
  error = AddHeaders(socket, request, (const WCHAR *)headers);
  if (error != NO_ERROR) {
    return error;
  }

  if (!Begin(socket, &socket->open, &socket->request)) {
    return ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0,
                          0, (DWORD_PTR)socket)) {
    return NotStarted(socket, &socket->open, GetLastError());
  }
  error = Wait(socket, &socket->open);
  if (error != NO_ERROR) {
    return error;
  }
  if (!Begin(socket, &socket->open, &socket->request)) {
    return ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  if (!WinHttpReceiveResponse(request, NULL)) {
    return NotStarted(socket, &socket->open, GetLastError());
  }
  error = Wait(socket, &socket->open);
  if (error != NO_ERROR) {
    return error;
  }

  DWORD status = 0;
  DWORD size = sizeof status;
  if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                           WINHTTP_HEADER_NAME_BY_INDEX, &status, &size,
                           WINHTTP_NO_HEADER_INDEX)) {
    return Outcome(socket, GetLastError());
  }
  *statusCode = status;
  if (status != HTTP_STATUS_SWITCH_PROTOCOLS) {
    return NO_ERROR;
  }

  // The upgrade's timeouts don't apply to the open connection, which may be
  // idle for a while. (Set on the request too, in case the socket takes its
  // timeouts from there.)
  DWORD idle = kIdleReceiveTimeout;
  WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_TIMEOUT, &idle, sizeof idle);
  HINTERNET webSocket = WinHttpWebSocketCompleteUpgrade(request, (DWORD_PTR)socket);
  if (!webSocket) {
    return Outcome(socket, GetLastError());
  }
  if (!Keep(socket, &socket->webSocket, webSocket, &error)) {
    return Outcome(socket, error);
  }
  WinHttpSetOption(webSocket, WINHTTP_OPTION_RECEIVE_TIMEOUT, &idle, sizeof idle);
  // The socket doesn't need the request once it's upgraded.
  Close(socket, &socket->request);
  return NO_ERROR;
}

uint32_t CWinHTTPSocketReceive(CWinHTTPSocket *socket, void *buffer, uint32_t length,
                               uint32_t *bytesRead, int32_t *received) {
  DWORD capacity = length < kReceiveBufferSize ? length : kReceiveBufferSize;
  for (;;) {
    HINTERNET webSocket = Get(socket, &socket->webSocket);
    if (!webSocket || !Begin(socket, &socket->receive, &socket->webSocket)) {
      return ERROR_WINHTTP_OPERATION_CANCELLED;
    }
    // In this mode, the byte count and buffer type come with the completion.
    DWORD error = WinHttpWebSocketReceive(webSocket, socket->receiveBuffer, capacity, NULL, NULL);
    if (error != NO_ERROR) {
      return NotStarted(socket, &socket->receive, error);
    }
    error = Wait(socket, &socket->receive);
    if (error == ERROR_WINHTTP_TIMEOUT) {
      continue;  // Idle; keep waiting.
    }
    if (error != NO_ERROR) {
      return error;
    }
    DWORD read = socket->receive.bytes;
    if (read > capacity) {
      read = capacity;
    }
    memcpy(buffer, socket->receiveBuffer, read);
    *bytesRead = read;
    switch (socket->receive.type) {
      case WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE:
      case WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE:
        *received = CWinHTTPReceivedFragment;
        break;
      case WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE:
        *received = CWinHTTPReceivedClose;
        break;
      default:
        *received = CWinHTTPReceivedMessage;
        break;
    }
    return NO_ERROR;
  }
}

uint32_t CWinHTTPSocketSend(CWinHTTPSocket *socket, const void *bytes, uint32_t length) {
  // WinHTTP may read the bytes until the send completes; the copy is the
  // socket's, so it outlives the call if it's cut short.
  BYTE *copy = malloc(length > 0 ? length : 1);
  if (!copy) {
    return ERROR_NOT_ENOUGH_MEMORY;
  }
  if (length > 0) {
    memcpy(copy, bytes, length);
  }
  AcquireSRWLockExclusive(&socket->lock);
  free(socket->sendBuffer);  // The previous send's, which has completed.
  socket->sendBuffer = copy;
  ReleaseSRWLockExclusive(&socket->lock);

  HINTERNET webSocket = Get(socket, &socket->webSocket);
  if (!webSocket || !Begin(socket, &socket->send, &socket->webSocket)) {
    return ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  DWORD error =
      WinHttpWebSocketSend(webSocket, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE, copy, length);
  if (error != NO_ERROR) {
    return NotStarted(socket, &socket->send, error);
  }
  return Wait(socket, &socket->send);
}

uint32_t CWinHTTPSocketShutdown(CWinHTTPSocket *socket) {
  HINTERNET webSocket = Get(socket, &socket->webSocket);
  if (!webSocket || !Begin(socket, &socket->shutdown, &socket->webSocket)) {
    return ERROR_WINHTTP_OPERATION_CANCELLED;
  }
  DWORD error =
      WinHttpWebSocketShutdown(webSocket, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, NULL, 0);
  if (error == ERROR_IO_PENDING) {
    return Wait(socket, &socket->shutdown);
  }
  // Done already (or failed): no callback.
  return NotStarted(socket, &socket->shutdown, error);
}

#else

// WinHTTP is Windows only; the target is empty elsewhere.
typedef int CWinHTTPUnavailable;

#endif  // defined(_WIN32)
