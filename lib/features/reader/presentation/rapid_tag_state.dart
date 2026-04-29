class RapidTagState {
  bool _armed = false;

  bool get isArmed => _armed;

  void arm() {
    _armed = true;
  }

  void reset() {
    _armed = false;
  }
}
