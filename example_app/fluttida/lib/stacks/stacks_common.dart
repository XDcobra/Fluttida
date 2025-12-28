import '../lab_screen.dart';

RequestResult fromNativeMap(
  Map<dynamic, dynamic>? map, {
  String noResponseError = 'No response from native channel.',
}) {
  if (map == null) {
    return RequestResult(
      status: null,
      body: '',
      durationMs: 0,
      error: noResponseError,
    );
  }
  final status = (map['status'] as num?)?.toInt();
  final body = (map['body'] as String?) ?? '';
  final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
  final error = map['error'] as String?;
  return RequestResult(
    status: status,
    body: body,
    durationMs: durationMs,
    error: error,
  );
}
