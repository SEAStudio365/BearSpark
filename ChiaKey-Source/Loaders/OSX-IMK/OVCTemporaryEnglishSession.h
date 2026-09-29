#pragma once

// Shared by all IMK controllers. Text clients may disappear or be replaced
// within one app, so their lifetime must not determine the language mode.
class OVCTemporaryEnglishSession {
 public:
  OVCTemporaryEnglishSession() : _application(0), _enabled(false) {}

  bool enabled() const { return _enabled; }
  void setEnabled(bool enabled) { _enabled = enabled; }

  void activateApplication(int application) {
    if (_application != application) {
      _enabled = false;
      _application = application;
    }
  }

  void deactivateApplication(int application) {
    // A late notification from the previous app must not reset the new app.
    if (_application == application) {
      _enabled = false;
      _application = 0;
    }
  }

  void inputSourceChanged() { _enabled = false; }

 private:
  int _application;
  bool _enabled;
};
