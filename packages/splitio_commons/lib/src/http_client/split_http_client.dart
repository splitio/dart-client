import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/sdk_version.dart';

class SplitHttpResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const SplitHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
}

class SplitHttpClient {
  final http.Client _client;
  final String _apiKey;
  final Duration _timeout;

  SplitHttpClient({
    required String apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  })  : _apiKey = apiKey,
        _client = client ?? http.Client(),
        _timeout = timeout;

  Future<SplitHttpResponse> get(
    String url, {
    Map<String, String>? queryParameters,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: queryParameters);
    final response = await _client
        .get(uri, headers: {..._headers(), ...?extraHeaders}).timeout(_timeout);
    return SplitHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  Future<SplitHttpResponse> post(
    String url, {
    Object? body,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse(url);
    final response = await _client
        .post(
          uri,
          headers: {
            ..._headers(),
            'Content-Type': 'application/json',
            ...?extraHeaders,
          },
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_timeout);
    return SplitHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  Map<String, String> _headers() => {
        'Authorization': 'Bearer $_apiKey',
        'SplitSDKVersion': sdkVersion,
      };

  void close() => _client.close();
}
