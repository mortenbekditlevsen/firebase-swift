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

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

// Checks a note and adds it to `notes`, with the server's time. Clients can't
// write notes themselves (firestore.rules).
exports.pinNote = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to pin notes.");
  }
  const text = typeof request.data?.text === "string" ? request.data.text.trim() : "";
  if (text.length === 0 || text.length > 1000) {
    throw new HttpsError("invalid-argument", "A note has 1 to 1000 characters.");
  }
  const name = typeof request.data?.authorName === "string" ? request.data.authorName.trim() : "";
  const note = await getFirestore().collection("notes").add({
    text,
    authorID: request.auth.uid,
    authorName: name.slice(0, 80) || "Anonymous",
    createdAt: FieldValue.serverTimestamp(),
    attachment: null,
  });
  return { id: note.id };
});

// Records an uploaded attachment (attachments/{uid}/{note}/{file}) on its note,
// if the uploader wrote the note.
exports.describeAttachment = onObjectFinalized(async (event) => {
  const [folder, uid, noteID, ...rest] = event.data.name.split("/");
  if (folder !== "attachments" || !uid || !noteID || rest.length === 0) {
    return;
  }
  const ref = getFirestore().collection("notes").doc(noteID);
  const note = await ref.get();
  if (!note.exists || note.get("authorID") !== uid) {
    return;
  }
  await ref.update({
    attachment: {
      path: event.data.name,
      name: rest.join("/"),
      size: Number(event.data.size),
      contentType: event.data.contentType ?? "application/octet-stream",
    },
  });
});
