import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data != null) {
      // ignore: avoid_print
      print('[D3C-T02-DRIVER-REPORT] ${jsonEncode(data)}');
    }
  },
);
