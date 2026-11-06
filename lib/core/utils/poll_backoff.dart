/// Interval for a safety-net poll that slows down while requests fail, so a
/// struggling database isn't hit at full rate by every open screen.
class PollBackoff {
  PollBackoff({required this.base, required this.max}) : _current = base;

  final Duration base;
  final Duration max;
  Duration _current;

  Duration get current => _current;

  void failed() {
    final doubled = _current * 2;
    _current = doubled > max ? max : doubled;
  }

  void succeeded() => _current = base;
}
