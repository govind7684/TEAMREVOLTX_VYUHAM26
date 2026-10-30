abstract class AppException implements Exception {
  const AppException();
  String get message;
  @override
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(this.errors);
  final List<String> errors;
  @override
  String get message => errors.join('\n');
}

class PermissionDeniedException extends AppException {
  const PermissionDeniedException(this.message);
  @override
  final String message;
}

class NotFoundException extends AppException {
  const NotFoundException([this.message = 'That record was not found.']);
  @override
  final String message;
}

/// Turns any error into text that is safe to show a person.
String friendlyError(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Nothing was changed. Please try again.';
}
