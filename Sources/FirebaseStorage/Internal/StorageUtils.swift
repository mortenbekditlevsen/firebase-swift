// Copyright 2022 Google LLC
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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


#if canImport(UniformTypeIdentifiers)
private import UniformTypeIdentifiers
#endif

enum StorageUtils {
  static func defaultRequestForReference(reference: StorageReference,
                                        queryParams: [String: String]? = nil)
    -> URLRequest {
    var components = URLComponents()
    components.scheme = reference.storage.scheme
    components.host = reference.storage.host
    components.port = reference.storage.port

    if let queryParams {
      var queryItems = [URLQueryItem]()
      for (key, value) in queryParams {
        queryItems.append(URLQueryItem(name: key, value: value))
      }
      components.queryItems = queryItems
      // NSURLComponents does not encode "+" as "%2B". This is however required by our backend, as
      // it treats "+" as a shorthand encoding for spaces. See also
      // https://stackoverflow.com/questions/31577188/how-to-encode-into-2b-with-nsurlcomponents
      components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
        of: "+",
        with: "%2B"
      )
    }
    let encodedPath = encodedURL(for: reference.path)
    components.percentEncodedPath = encodedPath
    guard let url = components.url else {
      fatalError("FirebaseStorage Internal Error: Failed to create url for \(reference.bucket)")
    }
    return URLRequest(url: url)
  }

  static func encodedURL(for path: StoragePath) -> String {
    let bucketString = "/b/\(GCSEscapedString(path.bucket))"
    var objectString: String
    if let objectName = path.object {
      objectString = "/o/\(GCSEscapedString(objectName))"
    } else {
      objectString = "/o"
    }
    return "/v0\(bucketString)\(objectString)"
  }

    static func GCSEscapedString(_ string: String) -> String {
    // This is the list at https://cloud.google.com/storage/docs/json_api/ without &, ; and +.
    let allowedSet =
      CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*,=:@"
      )
    return string.addingPercentEncoding(withAllowedCharacters: allowedSet)!
  }

  static func MIMETypeForExtension(_ fileExtension: String?) -> String {
    guard let fileExtension else {
      return "application/octet-stream"
    }
    #if canImport(UniformTypeIdentifiers)
      return UTType(filenameExtension: fileExtension)?.preferredMIMEType
        ?? "application/octet-stream"
    #else
      // No system type database on Linux, Windows or Android; cover the common cases.
      return commonMIMETypes[fileExtension.lowercased()] ?? "application/octet-stream"
    #endif
  }

  #if !canImport(UniformTypeIdentifiers)
    private static let commonMIMETypes: [String: String] = [
      "txt": "text/plain", "html": "text/html", "htm": "text/html", "css": "text/css",
      "csv": "text/csv", "js": "text/javascript", "json": "application/json",
      "xml": "application/xml", "pdf": "application/pdf", "zip": "application/zip",
      "gz": "application/gzip", "png": "image/png", "jpg": "image/jpeg",
      "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
      "svg": "image/svg+xml", "heic": "image/heic", "mp3": "audio/mpeg",
      "m4a": "audio/mp4", "wav": "audio/wav", "mp4": "video/mp4",
      "mov": "video/quicktime", "webm": "video/webm",
    ]
  #endif
}
