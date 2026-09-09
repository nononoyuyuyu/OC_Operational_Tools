import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// 本文・HTTP例外を利用者へ漏らさず、呼出し元で安全なエラーへ変換する。
class ResponseTooLarge implements Exception {
  const ResponseTooLarge();
}

/// Content-Lengthが欠落・過少でも、実際に受信したバイト数を制限する。
Future<http.Response> readBoundedResponse(
  http.StreamedResponse response, {
  required int maxBytes,
  required void Function() abort,
}) async {
  final reader = StreamIterator<List<int>>(response.stream);
  try {
    if ((response.contentLength ?? 0) > maxBytes) {
      throw const ResponseTooLarge();
    }
    final body = BytesBuilder();
    while (await reader.moveNext()) {
      final chunk = reader.current;
      if (chunk.length > maxBytes - body.length) {
        throw const ResponseTooLarge();
      }
      body.add(chunk);
    }
    return http.Response.bytes(
      body.takeBytes(),
      response.statusCode,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  } on ResponseTooLarge {
    abort();
    rethrow;
  } finally {
    await reader.cancel();
  }
}
