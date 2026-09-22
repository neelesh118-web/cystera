import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  // Required before the first frame: the lock controller reads the keystore and
  // sets the screen-security flag through platform channels.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CysteraApp());
}
