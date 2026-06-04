import 'package:flutter/cupertino.dart';

class AppRoute {
  static CupertinoPageRoute<T> push<T>(Widget page) =>
      CupertinoPageRoute<T>(builder: (_) => page);

  static CupertinoPageRoute<T> modal<T>(Widget page) =>
      CupertinoPageRoute<T>(builder: (_) => page, fullscreenDialog: true);
}
